import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';
import 'api_exceptions.dart';

/// Provider for the UploaderService
final uploaderServiceProvider = Provider<UploaderService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final service = UploaderService(apiClient);
  ref.onDispose(service.dispose);
  return service;
});

class UploaderService {
  static const int _maxUploadBytes = 25 * 1024 * 1024; // 25 MB safety cap

  final ApiClient _apiClient;

  /// Dedicated unauthenticated Dio client for direct MinIO/S3 PUT uploads
  /// (never attaches Klinciti JWT headers; reuses TLS connections).
  final Dio _uploadDio;

  UploaderService(this._apiClient)
    : _uploadDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

  void dispose() {
    _uploadDio.close(force: true);
  }

  /// Uploads a file directly to cloud storage (MinIO/S3) via a backend Presigned URL.
  /// Compresses images (including HEIC/HEIF -> JPEG) and strips EXIF GPS metadata.
  Future<String> uploadFileDirectly({
    required File file,
    required String endpoint,
    Map<String, dynamic>? payloadData,
    bool compress = true,
    String imageContext = 'profile', // 'profile', 'jobs', 'banner', 'chats'
    bool isGetRequest = false,
  }) async {
    File fileToUpload = file;
    File? tempCompressedFile;

    try {
      if (!await file.exists()) {
        throw ApiException('Выбранный файл не найден');
      }

      final originalName = _sanitizeFileName(p.basename(file.path));
      String finalFileName = originalName;

      // 1. Client-Side Image Compression & EXIF GPS Stripping (skip GIFs)
      final ext = p.extension(originalName).toLowerCase();
      final isCompressibleImage = _isCompressibleImageExtension(ext);

      if (compress && isCompressibleImage) {
        final isProfile = imageContext == 'profile';
        final isBanner = imageContext == 'banner';

        final int targetDimension = isProfile ? 600 : 1920;
        final int quality = isProfile ? 70 : (isBanner ? 90 : 80);

        try {
          final baseName = _sanitizeBaseName(
            p.basenameWithoutExtension(originalName),
          );
          finalFileName = '$baseName.jpg';

          final tempDir = await getTemporaryDirectory();
          final targetPath = p.join(
            tempDir.path,
            'upload_${DateTime.now().microsecondsSinceEpoch}_$finalFileName',
          );

          final XFile? compressed =
              await FlutterImageCompress.compressAndGetFile(
                file.absolute.path,
                targetPath,
                quality: quality,
                minWidth: targetDimension,
                minHeight: targetDimension,
                format: CompressFormat.jpeg,
                keepExif: false, // Strip GPS & device EXIF for user privacy
                autoCorrectionAngle: true,
              );

          if (compressed != null) {
            tempCompressedFile = File(compressed.path);
            fileToUpload = tempCompressedFile;
          }
        } catch (error) {
          if (kDebugMode) {
            log(
              'Client-side compression failed, falling back to original file: $error',
              name: 'UploaderService',
            );
          }
          finalFileName = originalName;
          fileToUpload = file;
        }
      }

      // 2. Validate file size before requesting a presigned URL
      final fileLength = await fileToUpload.length();
      if (fileLength <= 0) {
        throw ApiException('Файл пуст и не может быть загружен');
      }
      if (fileLength > _maxUploadBytes) {
        throw ApiException('Размер файла превышает допустимый предел (25 МБ)');
      }

      // 3. Request Presigned URL from the Fastify backend
      final requestBody = <String, dynamic>{
        ...?payloadData,
        'fileName': finalFileName,
      };

      final Response<dynamic> presignedResponse = isGetRequest
          ? await _apiClient.dio.get(endpoint, queryParameters: requestBody)
          : await _apiClient.dio.post(endpoint, data: requestBody);

      final rawBody = presignedResponse.data is Map
          ? Map<String, dynamic>.from(presignedResponse.data as Map)
          : <String, dynamic>{};
      final data = rawBody['data'] is Map
          ? Map<String, dynamic>.from(rawBody['data'] as Map)
          : rawBody;

      final String uploadUrl =
          (data['url'] ?? data['uploadUrl'] ?? data['presignedUrl'] ?? '')
              .toString()
              .trim();
      final String publicUrl = (data['publicUrl'] ?? '').toString().trim();
      final String mimeType =
          (data['mimeType'] ?? '').toString().trim().isNotEmpty
          ? data['mimeType'].toString().trim()
          : _inferMimeType(finalFileName);

      if (uploadUrl.isEmpty || publicUrl.isEmpty) {
        throw ApiException('Сервер не вернул ссылку для загрузки файла');
      }

      if (kReleaseMode && !uploadUrl.startsWith('https://')) {
        throw ApiException('Небезопасный URL хранилища в production-сборке');
      }

      // 4. Stream file directly to Cloud Storage via unauthenticated PUT
      final uploadResult = await _uploadDio.put<dynamic>(
        uploadUrl,
        data: fileToUpload.openRead(),
        options: Options(
          headers: {
            Headers.contentLengthHeader: fileLength,
            Headers.contentTypeHeader: mimeType,
          },
        ),
      );

      final statusCode = uploadResult.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        throw ApiException('Ошибка хранилища при загрузке файла ($statusCode)');
      }

      return publicUrl;
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    } catch (e) {
      if (kDebugMode) {
        log('Upload failed: $e', name: 'UploaderService');
      }
      throw ApiException('Не удалось загрузить файл. Попробуйте еще раз.');
    } finally {
      // Always clean up temporary compressed files, even when uploads fail
      if (tempCompressedFile != null && tempCompressedFile.path != file.path) {
        try {
          if (await tempCompressedFile.exists()) {
            await tempCompressedFile.delete();
          }
        } catch (_) {
          // Best-effort temp cache cleanup
        }
      }
    }
  }

  bool _isCompressibleImageExtension(String ext) {
    return ext == '.png' ||
        ext == '.jpg' ||
        ext == '.jpeg' ||
        ext == '.webp' ||
        ext == '.heic' ||
        ext == '.heif';
  }

  String _sanitizeBaseName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (cleaned.isEmpty) return 'file';
    return cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
  }

  String _sanitizeFileName(String rawName) {
    final ext = p.extension(rawName).toLowerCase();
    final base = _sanitizeBaseName(p.basenameWithoutExtension(rawName));
    return '$base$ext';
  }

  String _inferMimeType(String name) {
    switch (p.extension(name).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.heic':
        return 'image/heic';
      case '.heif':
        return 'image/heif';
      case '.pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }
}

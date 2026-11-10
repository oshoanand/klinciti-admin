import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';
import 'api_exceptions.dart'; // Ensure this exists in your project

/// Provider for the UploaderService
final uploaderServiceProvider = Provider<UploaderService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return UploaderService(apiClient);
});

class UploaderService {
  final ApiClient _apiClient;

  UploaderService(this._apiClient);

  /// Uploads a file directly to the cloud (MinIO/S3) using a Presigned URL.
  /// Safely handles images (with compression) mimicking the web behavior.
  Future<String> uploadFileDirectly({
    required File file,
    required String endpoint,
    Map<String, dynamic>? payloadData,
    bool compress = true,
    String imageContext = 'profile', // 'profile', 'jobs', 'banner', 'chats'
    bool isGetRequest = false, // ✅ Set to true when using with the Chat backend
  }) async {
    try {
      File fileToUpload = file;
      String originalName = file.path.split('/').last.toLowerCase();
      String finalFileName = originalName;

      // 1. Client-Side Compression (Images only, skip GIFs)
      final isImage = _isImageExtension(originalName);
      final isGif = originalName.endsWith('.gif');

      if (compress && isImage && !isGif) {
        final isProfile = imageContext == 'profile';
        final isBanner = imageContext == 'banner';

        // Match Web quality and sizing thresholds
        final int targetWidth = isProfile ? 600 : 1920;
        final int quality = isProfile ? 70 : (isBanner ? 90 : 80);

        try {
          // Force .jpg extension for standardized cloud delivery
          final baseName = originalName.split('.').first;
          finalFileName = '$baseName.jpg';

          // Get a temporary directory to save the compressed file
          final tempDir = await getTemporaryDirectory();
          final targetPath =
              '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_$finalFileName';

          final XFile? compressedFile =
              await FlutterImageCompress.compressAndGetFile(
                file.absolute.path,
                targetPath,
                quality: quality,
                minWidth: targetWidth,
                minHeight: targetWidth,
                format: CompressFormat.jpeg,
              );

          if (compressedFile != null) {
            fileToUpload = File(compressedFile.path);
          }
        } catch (error) {
          // Fallback to original file if compression fails
          print(
            'Client-side compression failed, proceeding with original file: $error',
          );
          finalFileName = originalName;
        }
      }

      // 2. Build the exact payload
      final requestBody = {...?payloadData, 'fileName': finalFileName};

      // 3. Request the Presigned URL from the Fastify Backend
      // Support both GET and POST depending on the endpoint design
      final Response presignedResponse;
      if (isGetRequest) {
        presignedResponse = await _apiClient.dio.get(
          endpoint,
          queryParameters: requestBody,
        );
      } else {
        presignedResponse = await _apiClient.dio.post(
          endpoint,
          data: requestBody,
        );
      }

      // ✅ Map backend response safely ('url' is from our Fastify chat backend)
      final String uploadUrl =
          presignedResponse.data['url'] ??
          presignedResponse.data['uploadUrl'] ??
          presignedResponse.data['presignedUrl'];

      final String publicUrl = presignedResponse.data['publicUrl'];
      final String mimeType =
          presignedResponse.data['mimeType'] ?? _inferMimeType(finalFileName);

      // 4. Upload directly to Cloud Storage via PUT request
      // ✅ We use a fresh, unauthenticated Dio instance to bypass JWT interceptors (prevents MinIO Auth errors)
      final uploadDio = Dio();
      final fileLength = await fileToUpload.length();

      final uploadResult = await uploadDio.put(
        uploadUrl,
        data: fileToUpload.openRead(),
        options: Options(
          headers: {
            Headers.contentLengthHeader: fileLength,
            Headers.contentTypeHeader: mimeType,
          },
          sendTimeout: null, // Remove timeouts for large uploads
          receiveTimeout: null,
        ),
      );

      if (uploadResult.statusCode != 200 && uploadResult.statusCode != 201) {
        throw Exception(
          'Failed to upload file to storage bucket: ${uploadResult.statusCode}',
        );
      }

      // Clean up the temporary compressed file to free up cache space
      if (fileToUpload.path != file.path && await fileToUpload.exists()) {
        await fileToUpload.delete();
      }

      // 5. Return the public URL
      return publicUrl;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    } catch (e) {
      throw ApiException('Ошибка при загрузке файла: $e');
    }
  }

  /// Helper to determine if the file is an image based on extension
  bool _isImageExtension(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  /// Determines the MIME type based on file extension
  String _inferMimeType(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.endsWith('.png')) return 'image/png';
    if (lowerName.endsWith('.webp')) return 'image/webp';
    if (lowerName.endsWith('.gif')) return 'image/gif';
    if (lowerName.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg'; // Default for compressed images
  }
}

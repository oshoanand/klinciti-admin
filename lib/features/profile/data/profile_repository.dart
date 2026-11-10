import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import 'profile_model.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(apiClientProvider));
});

class ProfileRepository {
  final ApiClient _api;

  ProfileRepository(this._api);

  Future<ProfileModel> fetchProfile() async {
    try {
      final res = await _api.dio.get('/admin/profile');
      return ProfileModel.fromJson(res.data);
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    try {
      final res = await _api.dio.patch('/admin/profile', data: data);
      return res.data; // Returning the raw data to let the provider extract the updated 'user' object
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> uploadAndSetAvatar(File file) async {
    try {
      final fileName = p.basename(file.path);

      // 1. Get Presigned URL
      final presignedRes = await _api.dio.post(
        '/admin/profile/upload-url',
        data: {'folder': 'profileImage', 'fileName': fileName},
      );

      final String uploadUrl = presignedRes.data['presignedUrl'];
      final String finalImageUrl = presignedRes.data['publicUrl'];
      final String mimeType = presignedRes.data['headers']['Content-Type'];

      // 2. Upload file to MinIO (Using raw Dio to avoid sending Auth headers to MinIO)
      final rawDio = Dio();
      final bytes = await file.readAsBytes();
      await rawDio.put(
        uploadUrl,
        data: Stream.fromIterable(bytes.map((e) => [e])),
        options: Options(
          headers: {
            Headers.contentLengthHeader: bytes.length,
            Headers.contentTypeHeader: mimeType,
          },
        ),
      );

      // 3. Instantly update the database with the new Avatar URL
      final res = await _api.dio.patch(
        '/admin/profile',
        data: {'avatarUrl': finalImageUrl},
      );

      return res.data;
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}

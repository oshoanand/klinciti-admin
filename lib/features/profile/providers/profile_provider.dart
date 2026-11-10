import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/profile_model.dart';
import '../data/profile_repository.dart';
import '../../auth/providers/auth_provider.dart';

// ==========================================
// 1. FETCH PROVIDER (READ)
// ==========================================
final customerProfileProvider = FutureProvider.autoDispose<ProfileModel>((ref) {
  final repository = ref.watch(profileRepositoryProvider);
  return repository.fetchProfile();
});

// ==========================================
// 2. MUTATION PROVIDER (UPDATE)
// ==========================================
final profileMutationProvider =
    StateNotifierProvider.autoDispose<ProfileMutationNotifier, bool>((ref) {
      return ProfileMutationNotifier(ref.watch(profileRepositoryProvider), ref);
    });

class ProfileMutationNotifier extends StateNotifier<bool> {
  final ProfileRepository _repository;
  final Ref _ref;

  ProfileMutationNotifier(this._repository, this._ref) : super(false);

  Future<void> updateProfile(Map<String, dynamic> data) async {
    state = true;
    try {
      final responseData = await _repository.updateProfile(data);

      // Sync the global auth state with the updated user data for the Drawer
      if (responseData['user'] != null) {
        _ref.read(currentUserProvider.notifier).state = responseData['user'];
      }

      _ref.invalidate(customerProfileProvider);
      state = false;
    } catch (e) {
      state = false;
      rethrow; // UI catches this via ApiException
    }
  }

  Future<void> uploadAndSetAvatar(File file) async {
    state = true;
    try {
      final responseData = await _repository.uploadAndSetAvatar(file);

      // Sync the global auth state with the updated avatar for the Drawer
      if (responseData['user'] != null) {
        _ref.read(currentUserProvider.notifier).state = responseData['user'];
      }

      _ref.invalidate(customerProfileProvider);
      state = false;
    } catch (e) {
      state = false;
      rethrow;
    }
  }
}

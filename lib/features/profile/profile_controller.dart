import 'dart:io';
import 'package:duri_care/core/services/profile_service.dart';
import 'package:duri_care/core/utils/helpers/dialog_helper.dart';
import 'package:duri_care/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

class ProfileController extends GetxController {
  final AuthController authController = Get.find<AuthController>();
  final ProfileService _profileService = Get.find<ProfileService>();

  final RxString username = ''.obs;
  final RxString email = ''.obs;
  final RxString password = ''.obs;
  final RxString confirmPassword = ''.obs;
  final RxString profilePicture = ''.obs;
  final RxString role = ''.obs;
  final RxBool isNotificationEnabled = true.obs;
  final isPasswrodVisible = true.obs;
  final isConfirmPasswordVisible = true.obs;

  late TextEditingController usernameController;
  late TextEditingController emailController;
  late TextEditingController passwordController;
  late TextEditingController confirmPasswordController;

  final formKey = GlobalKey<FormState>();
  final Rx<File?> imageFile = Rx<File?>(null);
  final ImagePicker _picker = ImagePicker();

  @override
  void onInit() {
    super.onInit();
    usernameController = TextEditingController();
    emailController = TextEditingController();
    passwordController = TextEditingController();
    confirmPasswordController = TextEditingController();
    _initializeProfileData();
  }

  void toggleNotification() {
    isNotificationEnabled.value = !isNotificationEnabled.value;
  }

  void togglePasswordVisibility() {
    isPasswrodVisible.value = !isPasswrodVisible.value;
  }

  void toggleConfirmPasswordVisibility() {
    isConfirmPasswordVisible.value = !isConfirmPasswordVisible.value;
  }

  Future<void> _initializeProfileData() async {
    username.value = await authController.getUsername();
    email.value = await authController.getEmail() ?? '';
    profilePicture.value = await authController.getProfilePicture();
    role.value = await authController.getRole() ?? 'Employee';

    usernameController.text = username.value;
    emailController.text = email.value;
    passwordController.text = password.value;
    confirmPasswordController.text = confirmPassword.value;
  }

  Future<void> pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 800,
      );
      if (pickedFile != null) {
        imageFile.value = File(pickedFile.path);
      }
    } catch (e) {
      DialogHelper.showErrorDialog(
        title: 'Error',
        message: 'Gagal memilih gambar: ${e.toString()}',
      );
    }
  }

  Future<void> updateProfile() async {
    if (_profileService.getCurrentUser() == null) return;

    if (!formKey.currentState!.validate()) {
      DialogHelper.showErrorDialog(
        title: 'Error',
        message:
            'Form tidak valid. Mohon periksa kembali data yang dimasukkan.',
      );
      return;
    }

    if (passwordController.text.isNotEmpty ||
        confirmPasswordController.text.isNotEmpty) {
      if (passwordController.text != confirmPasswordController.text) {
        DialogHelper.showErrorDialog(
          title: 'Error',
          message: 'Password dan konfirmasi password tidak sesuai.',
        );
        return;
      }
    }

    try {
      String? uploadedImageUrl;
      if (imageFile.value != null) {
        uploadedImageUrl = await _profileService.uploadProfileImage(
          imageFile.value!,
        );
        if (uploadedImageUrl != null) {
          profilePicture.value = uploadedImageUrl;
        }
      }

      await _profileService.updateUserProfile(
        email:
            emailController.text != email.value ? emailController.text : null,
        password:
            passwordController.text.isNotEmpty ? passwordController.text : null,
        fullname: usernameController.text,
        profileImageUrl: uploadedImageUrl,
      );

      username.value = usernameController.text;
      email.value = emailController.text;

      Get.back();
      DialogHelper.showSuccessDialog(
        title: 'Berhasil',
        message: 'Profil berhasil diperbarui',
      );
    } catch (e) {
      DialogHelper.showErrorDialog(
        title: 'Error',
        message: 'Gagal memperbarui profil: ${e.toString()}',
      );
    }
  }

  String? validateEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (email.isEmpty) {
      return 'Email tidak boleh kosong';
    } else if (!emailRegex.hasMatch(email)) {
      return 'Format email tidak valid';
    }
    return null;
  }

  String? validatePassword(String password) {
    if (password.isEmpty) {
      return null; // Allow empty password (no change)
    } else if (password.length < 6) {
      return 'Password minimal 6 karakter';
    }
    return null;
  }

  String? validateConfirmPassword(String password) {
    if (passwordController.text.isEmpty && password.isEmpty) {
      return null; // Both fields empty is valid (no change)
    } else if (passwordController.text.isNotEmpty && password.isEmpty) {
      return 'Konfirmasi password tidak boleh kosong';
    } else if (passwordController.text != password) {
      return 'Konfirmasi password tidak sesuai';
    }
    return null;
  }

  Future<void> logout() async {
    try {
      DialogHelper.showConfirmationDialog(
        title: 'Keluar Aplikasi?',
        message: 'Apakah anda yakin ingin keluar dari aplikasi ini?',
        onConfirm: () async {
          await _profileService.signOut();
          authController.logout();
          Get.offAllNamed('/login');
          DialogHelper.showSuccessDialog(
            title: 'Berhasil',
            message: 'Anda telah keluar dari aplikasi',
          );
        },
        onCancel: () {
          Get.back();
        },
      );
    } catch (e) {
      DialogHelper.showErrorDialog(
        title: 'Error',
        message: 'Gagal keluar: ${e.toString()}',
      );
    }
  }
}

import 'package:duri_care/core/services/zone_service.dart';
import 'package:duri_care/core/utils/helpers/dialog_helper.dart';
import 'package:duri_care/models/iot_device_model.dart';
import 'package:duri_care/models/zone_model.dart';
import 'package:duri_care/models/zone_schedule.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get_storage/get_storage.dart';
import 'dart:async';

class ZoneController extends GetxController {
  final ZoneService _zoneService = Get.find<ZoneService>();
  final zones = <Map<String, dynamic>>[].obs;
  final selectedZone = <String, dynamic>{}.obs;
  final RxBool isActive = false.obs;
  final storage = GetStorage();
  final RxInt activeCount = 0.obs;
  final RxBool isLoadingSchedules = false.obs;
  final Map<int, Timer> _scheduleTimers = {};

  final zoneCodes = [1, 2, 3, 4, 5, 6, 7, 8].obs;
  final RxInt selectedZoneCode = 1.obs;

  final Map<String, Timer?> _zoneTimers = {};
  final RxMap<String, RxString> zoneTimers = <String, RxString>{}.obs;

  final RxString moisture = '0%'.obs;
  final RxString temperature = '0°C'.obs;
  final RxString humidity = '0%'.obs;

  final selectedDate = Rx<DateTime?>(DateTime.now());
  final selectedTime = Rx<TimeOfDay?>(const TimeOfDay(hour: 6, minute: 0));
  final duration = 5.obs;
  final schedules = <ZoneScheduleModel>[].obs;

  final TextEditingController zoneNameController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  RxBool isLoadingDevices = false.obs;
  final devices = <IotDeviceModel>[].obs;
  final selectedDeviceIds = <int>[].obs;

  final isLoading = false.obs;

  // Helper method to convert ZoneModel to Map<String, dynamic>
  Map<String, dynamic> _zoneModelToMap(ZoneModel model) {
    return {
      'id': model.id,
      'zone_code': model.zoneCode,
      'name': model.name,
      'isActive': model.isActive,
      'created_at': model.createdAt.toIso8601String(),
      'deleted_at': model.deletedAt,
    };
  }

  @override
  void onInit() {
    super.onInit();
    isActive.value = storage.read('isActive') ?? false;

    loadZones().then((_) {
      _setupZoneTimers();
      listenToZoneChanges();
      countActive();
      loadAllZoneSchedules();
    });

    loadSchedules();
    loadDevices();
  }

  @override
  void onClose() {
    _zoneTimers.forEach((_, timer) => timer?.cancel());
    clearForm();
    super.onClose();
  }

  void _setupZoneTimers() {
    for (var zone in zones) {
      final zoneId = zone['id']?.toString();
      if (zoneId != null) {
        zoneTimers.putIfAbsent(zoneId, () => '00:00:00'.obs);

        if (zone['isActive'] == true) {
          startTimer(zoneId, duration.value);
        }

        final remainingTime = storage.read('timer_$zoneId');
        if (remainingTime != null && remainingTime > 0) {
          startTimer(zoneId, duration.value);
        }
      }
    }
  }

  /// Loads all zones for the current user
  Future<void> loadZones() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        DialogHelper.showErrorDialog(
          title: 'Authentication Error',
          message: 'User not logged in. Please log in to view your zones.',
        );
        return;
      }

      final zoneModels = await _zoneService.loadZones(userId);
      zones.value = zoneModels.map((model) => _zoneModelToMap(model)).toList();
    } catch (e) {
      DialogHelper.showErrorDialog(
        title: 'Failed to Load Zones',
        message: 'Error: ${e.toString()}',
      );
    }
  }

  /// Loads a specific zone by ID
  Future<void> loadZoneById(String zoneId) async {
    if (zoneId.isEmpty) return;

    isLoading.value = true;
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        DialogHelper.showErrorDialog(
          title: 'Authentication Error',
          message: 'User not logged in. Please log in to view your zones.',
        );
        isLoading.value = false;
        return;
      }

      ZoneModel zoneModel = await _zoneService.loadZoneById(zoneId, userId);
      Map<String, dynamic> zoneMap = _zoneModelToMap(zoneModel);
      zoneMap['timer'] = zoneTimers[zoneId]?.value ?? '00:00:00';

      selectedZone.value = zoneMap;
      loadSchedules();

      isActive.value = zoneModel.isActive;
      storage.write('isActive', isActive.value);

      getSoilMoisture(zoneId);
      loadDevicesForZone(zoneId);
    } catch (e) {
      DialogHelper.showErrorDialog(
        title: 'Failed to Load Zone',
        message: 'Error: ${e.toString()}',
      );
    } finally {
      isLoading.value = false;
    }
  }

  // Load devices for a specific zone
  Future<void> loadDevicesForZone(String zoneId) async {
    try {
      devices.value = await _zoneService.loadDevicesForZone(zoneId);
    } catch (e) {
      DialogHelper.showErrorDialog(
        title: 'Error Loading Devices',
        message: 'Failed to load devices for zone: ${e.toString()}',
      );
    }
  }

  Future<void> getSoilMoisture(String zoneId) async {
    try {
      // Simulate sensor data
      moisture.value = '${60 + DateTime.now().second % 20}%';
      temperature.value = '${25 + DateTime.now().minute % 10}°C';
      humidity.value = '${60 + DateTime.now().hour % 25}%';

      if (selectedZone.isNotEmpty) {
        selectedZone['moisture'] = moisture.value;
      }
    } catch (e) {
      moisture.value = '60%';
      temperature.value = '28°C';
      humidity.value = '65%';
    }
  }

  /// Mengambil data perangkat IoT dari server
  Future<void> loadDevices() async {
    isLoadingDevices.value = true;
    try {
      devices.value = await _zoneService.loadAllDevices();
    } catch (e) {
      DialogHelper.showErrorDialog(
        title: 'Gagal Memuat Perangkat',
        message: 'Gagal memuat perangkat IoT: ${e.toString()}',
      );
    } finally {
      isLoadingDevices.value = false;
    }
  }

  /// Create a new zone
  Future<void> createZone() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final name = zoneNameController.text.trim();

    if (userId == null || name.isEmpty) {
      DialogHelper.showErrorDialog(
        title: 'Error',
        message: 'User belum login atau nama zona kosong.',
      );
      return;
    }

    try {
      isLoading.value = true;

      final zoneModel = await _zoneService.createZone(
        name: name,
        zoneCode: selectedZoneCode.value,
        userId: userId,
      );

      final zoneMap = _zoneModelToMap(zoneModel);
      final zoneId = zoneModel.id.toString();

      if (selectedDeviceIds.isNotEmpty) {
        await _zoneService.assignDevicesToZone(zoneId, selectedDeviceIds);
      }

      zones.add(zoneMap);
      zoneTimers.putIfAbsent(zoneId, () => '00:00:00'.obs);

      await DialogHelper.showSuccessDialog(
        title: 'Berhasil',
        message: '$name berhasil dibuat.',
      );
      zoneNameController.clear();
      selectedDeviceIds.clear();
      Get.offAllNamed('/main');
    } catch (e) {
      DialogHelper.showErrorDialog(
        title: 'Gagal membuat zona',
        message: e.toString(),
      );
    } finally {
      isLoading.value = false;
    }
  }

  /// Perform actual zone deletion in the database
  Future<void> deleteZone(int zoneId) async {
    try {
      isLoading.value = true;

      await DialogHelper.showConfirmationDialog(
        title: 'Hapus Zona',
        message: 'Apakah Anda yakin ingin menghapus ${selectedZone['name']}?',
        onConfirm: () async {
          await _zoneService.deleteZone(zoneId);

          zones.removeWhere((z) => z['id'] == zoneId);
          stopTimer(zoneId.toString());

          if (selectedZone['id'] == zoneId) {
            selectedZone.clear();
          }

          DialogHelper.showSuccessDialog(
            title: 'Berhasil',
            message: 'Zona berhasil dihapus.',
          );

          Get.offAllNamed('/main');
        },
        onCancel: Get.back,
      );
    } catch (e) {
      DialogHelper.showErrorDialog(
        title: 'Gagal hapus zona',
        message: e.toString(),
      );
    } finally {
      isLoading.value = false;
    }
  }

  /// Update an existing zone with new information
  Future<void> updateZone(String zoneId, {required String newName}) async {
    if (newName.trim().isEmpty) {
      DialogHelper.showErrorDialog(
        title: 'Nama Tidak Valid',
        message: 'Nama zona tidak boleh kosong.',
      );
      return;
    }

    try {
      isLoading.value = true;

      final updated = await _zoneService.updateZone(
        zoneId: zoneId,
        newName: newName.trim(),
        zoneCode: selectedZoneCode.value,
      );

      final updatedMap = _zoneModelToMap(updated);

      final index = zones.indexWhere((z) => z['id'].toString() == zoneId);
      if (index != -1) {
        final currentZone = zones[index];
        zones[index] = {
          ...updatedMap,
          'timer': currentZone['timer'] ?? '00:00:00',
          'moisture': currentZone['moisture'] ?? '60%',
        };
      }

      if (selectedZone['id'].toString() == zoneId) {
        selectedZone['name'] = newName.trim();
      }

      await DialogHelper.showSuccessDialog(
        title: 'Berhasil',
        message: 'Zona berhasil diperbarui.',
      );
      Get.back();
    } catch (e) {
      DialogHelper.showErrorDialog(
        title: 'Gagal update',
        message: e.toString(),
      );
    } finally {
      isLoading.value = false;
    }
  }

  /// Toggle active state for a specific zone
  Future<void> toggleActive(dynamic zoneId, {bool fromtimer = false}) async {
    if (zoneId == null) return;

    final zoneIdStr = zoneId.toString();

    try {
      final updatedZone = await _zoneService.toggleZoneActive(zoneId);
      final updatedMap = _zoneModelToMap(updatedZone);

      final zoneIndex = zones.indexWhere(
        (z) => z['id'].toString() == zoneIdStr,
      );

      if (zoneIndex != -1) {
        final newActiveState = updatedZone.isActive;
        zones[zoneIndex] = {
          ...updatedMap,
          'timer': zones[zoneIndex]['timer'] ?? '00:00:00',
          'moisture': zones[zoneIndex]['moisture'] ?? '60%',
        };

        if (selectedZone['id'].toString() == zoneIdStr) {
          selectedZone['isActive'] = newActiveState;
          isActive.value = newActiveState;
        }

        if (newActiveState) {
          activeCount.value += 1;
          startTimer(zoneIdStr, duration.value);
        } else {
          activeCount.value -= 1;
          stopTimer(zoneIdStr);
        }

        storage.write('zone_active_$zoneIdStr', newActiveState);
      }
    } catch (e) {
      DialogHelper.showErrorDialog(title: 'Error', message: e.toString());
    }
  }

  void listenToZoneChanges() {
    _zoneService.zoneChangesStream().listen((updates) {
      for (final update in updates) {
        final updatedZone = update['new'];
        if (updatedZone == null) continue;

        final updatedZoneId = updatedZone['id']?.toString();
        if (updatedZoneId == null) continue;

        final updatedIsActive = updatedZone['isActive'] ?? false;

        final zoneIndex = zones.indexWhere(
          (z) => z['id'].toString() == updatedZoneId,
        );
        if (zoneIndex != -1) {
          final existingZone = zones[zoneIndex];
          zones[zoneIndex] = {
            ...existingZone,
            ...updatedZone,
            'timer': existingZone['timer'] ?? '00:00:00',
            'moisture': existingZone['moisture'] ?? '60%',
          };

          if (updatedIsActive && _zoneTimers[updatedZoneId] == null) {
            startTimer(updatedZoneId, duration.value);
          } else if (!updatedIsActive && _zoneTimers[updatedZoneId] != null) {
            stopTimer(updatedZoneId);
          }

          if (selectedZone['id']?.toString() == updatedZoneId) {
            selectedZone.value = {
              ...selectedZone,
              ...updatedZone,
              'timer': selectedZone['timer'] ?? '00:00:00',
              'moisture': selectedZone['moisture'] ?? '60%',
            };
            isActive.value = updatedIsActive;
          }
        }
      }
    });
  }

  Future<void> startTimer(String zoneId, int durationMinutes) async {
    if (_zoneTimers[zoneId] != null) {
      _zoneTimers[zoneId]?.cancel();
      _zoneTimers[zoneId] = null;
    }

    int totalSeconds = durationMinutes * 60;
    final storedSeconds = storage.read('timer_$zoneId');

    if (storedSeconds != null) {
      try {
        totalSeconds = int.parse(storedSeconds.toString());
      } catch (e) {
        DialogHelper.showErrorDialog(
          title: 'Error Parsing Timer',
          message: 'Error parsing timer value: $e',
        );
      }
    }

    // Initialize the timer display
    zoneTimers.putIfAbsent(zoneId, () => '00:00:00'.obs);

    const oneSecond = Duration(seconds: 1);
    _zoneTimers[zoneId] = Timer.periodic(oneSecond, (timer) {
      if (totalSeconds > 0) {
        totalSeconds--;
        final hours = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
        final minutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(
          2,
          '0',
        );
        final seconds = (totalSeconds % 60).toString().padLeft(2, '0');

        if (zoneTimers.containsKey(zoneId)) {
          zoneTimers[zoneId]?.value = '$hours:$minutes:$seconds';
        }

        storage.write('timer_$zoneId', totalSeconds);
      } else {
        stopTimer(zoneId);
        toggleActive(zoneId, fromtimer: true);
      }
    });
  }

  void stopTimer(String zoneId) {
    _zoneTimers[zoneId]?.cancel();
    _zoneTimers[zoneId] = null;

    if (zoneTimers.containsKey(zoneId)) {
      zoneTimers[zoneId]?.value = '00:00:00';
    }

    storage.remove('timer_$zoneId');
  }

  Future<void> _executeScheduledIrrigation(
    String zoneId,
    int duration,
    int scheduleId,
  ) async {
    try {
      final zoneIndex = zones.indexWhere((z) => z['id'].toString() == zoneId);
      if (zoneIndex == -1) return;

      final isZoneActive = zones[zoneIndex]['isActive'] ?? false;
      if (!isZoneActive) {
        this.duration.value = duration;

        storage.remove('timer_$zoneId');
        await toggleActive(zoneId);
        stopTimer(zoneId);

        await startTimer(zoneId, duration);
        final updatedIndex = zones.indexWhere(
          (z) => z['id'].toString() == zoneId,
        );
        if (updatedIndex != -1) {
          zones.refresh();
        }
      }
    } catch (e) {
      DialogHelper.showErrorDialog(
        title: 'Gagal Memuat Jadwal',
        message: 'Error ketika memuat jadwal: $e',
      );
    } finally {
      _scheduleTimers.remove(scheduleId);
    }
  }

  Future<void> saveSchedule() async {
    if (selectedDate.value == null || selectedTime.value == null) {
      DialogHelper.showErrorDialog(
        title: 'Gagal Membuat Jadwal',
        message:
            'Tanggal dan waktu tidak boleh kosong. Silakan pilih tanggal dan waktu terlebih dahulu!',
      );
      return;
    }

    final zoneId = selectedZone['id'].toString();

    try {
      final time = selectedTime.value!;
      final now = DateTime.now();
      final combinedDateTime = DateTime(
        selectedDate.value!.year,
        selectedDate.value!.month,
        selectedDate.value!.day,
        time.hour,
        time.minute,
      );

      if (combinedDateTime.isBefore(now)) {
        DialogHelper.showErrorDialog(
          title: 'Gagal Membuat Jadwal',
          message:
              'Jadwal tidak boleh lebih awal dari waktu saat ini. Silakan pilih waktu yang lebih baru!',
        );
        return;
      }

      await _zoneService.createSchedule(
        scheduledDateTime: combinedDateTime,
        duration: duration.value,
        zoneId: zoneId,
      );

      loadSchedules();
      clearForm();

      DialogHelper.showSuccessDialog(
        title: 'Jadwal Berhasil Disimpan',
        message: 'Jadwal irigasi otomatis Anda berhasil disimpan.',
        onConfirm: () {
          clearForm();
        },
      );
    } catch (e) {
      DialogHelper.showErrorDialog(
        title: 'Gagal Menyimpan Jadwal',
        message: e.toString(),
      );
    }
  }

  Future<void> deleteSchedule(int scheduleId, int zoneId) async {
    try {
      await DialogHelper.showConfirmationDialog(
        title: 'Hapus Jadwal',
        message: 'Apakah Anda yakin ingin menghapus jadwal ini?',
        onConfirm: () async {
          Get.back();

          isLoadingSchedules.value = true;

          final isDeleted = await _zoneService.deleteSchedule(
            scheduleId,
            zoneId,
          );

          if (isDeleted) {
            schedules.removeWhere((s) => s.schedule.id == scheduleId);
            await loadSchedules();
            DialogHelper.showSuccessDialog(
              title: 'Berhasil',
              message: 'Jadwal berhasil dihapus.',
            );
          } else {
            DialogHelper.showErrorDialog(
              title: 'Gagal Menghapus Jadwal',
              message: 'Jadwal ini masih digunakan oleh zona lain.',
            );
          }

          isLoadingSchedules.value = false;
        },
        onCancel: Get.back,
      );
    } catch (e) {
      DialogHelper.showErrorDialog(
        title: 'Gagal Menghapus Jadwal',
        message: e.toString(),
      );
      isLoadingSchedules.value = false;
    }
  }

  Future<void> loadSchedules() async {
    isLoadingSchedules.value = true;
    final zoneId = selectedZone['id']?.toString();

    if (zoneId == null || zoneId.isEmpty) {
      isLoadingSchedules.value = false;
      return;
    }

    try {
      schedules.value = await _zoneService.loadZoneSchedules(zoneId);

      final now = DateTime.now();
      for (var item in schedules) {
        try {
          final scheduledAt = item.schedule.scheduledAt;
          final duration = item.schedule.duration;
          final scheduledId = item.schedule.id;

          if (scheduledAt.isAfter(now)) {
            final timeUntilSchedule = scheduledAt.difference(now);

            _scheduleTimers[scheduledId] = Timer(timeUntilSchedule, () {
              _executeScheduledIrrigation(
                item.zoneId.toString(),
                duration,
                scheduledId,
              );
            });
          }
        } catch (e) {
          DialogHelper.showErrorDialog(
            title: 'Failed to Parse Schedule',
            message: 'Error parsing schedule date: $e',
          );
        }
      }
    } catch (e) {
      schedules.value = [];
      DialogHelper.showErrorDialog(
        title: 'Failed to Load Schedules',
        message: 'Error: ${e.toString()}',
      );
    } finally {
      isLoadingSchedules.value = false;
    }
  }

  Future<void> loadAllZoneSchedules() async {
    try {
      // Cancel and clear all existing timers
      _scheduleTimers.forEach((id, timer) {
        timer.cancel();
      });
      _scheduleTimers.clear();

      // Fetch all schedules from the service
      final scheduleList = await _zoneService.loadAllZoneSchedules();
      final now = DateTime.now();

      // Clear any stale data from storage
      storage.remove('schedules');

      // Process and set up timers for the fetched schedules
      for (var item in scheduleList) {
        try {
          final scheduledId = item.schedule.id;
          final scheduledAt = item.schedule.scheduledAt;
          final duration = item.schedule.duration;
          final zoneId = item.zoneId.toString();

          if (scheduledAt.isAfter(now)) {
            final timeUntilSchedule = scheduledAt.difference(now);

            _scheduleTimers[scheduledId] = Timer(timeUntilSchedule, () {
              _executeScheduledIrrigation(zoneId, duration, scheduledId);
            });
          }
        } catch (e) {
          DialogHelper.showErrorDialog(
            title: 'Failed to Process Schedule',
            message: 'Error: $e',
          );
        }
      }
    } catch (e) {
      DialogHelper.showErrorDialog(
        title: 'Failed to Load Schedules',
        message: 'Error: ${e.toString()}',
      );
    }
  }

  Future<void> countActive() async {
    activeCount.value = await _zoneService.countActiveZones();
  }

  void selectDate(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDate.value ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (pickedDate != null && pickedDate != selectedDate.value) {
      selectedDate.value = pickedDate;
    }
  }

  void selectTime(BuildContext context) async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (pickedTime != null) {
      selectedTime.value = pickedTime;
    }
  }

  String? validateName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Nama zona tidak boleh kosong';
    }
    if (value.length < 3) {
      return 'Nama zona minimal 3 karakter';
    }
    return null;
  }

  void clearForm() {
    selectedZoneCode.value = 1;
    zoneNameController.clear();
    selectedDate.value = DateTime.now();
    selectedTime.value = const TimeOfDay(hour: 6, minute: 0);
    duration.value = 5;
  }
}

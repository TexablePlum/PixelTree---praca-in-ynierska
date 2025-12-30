import 'dart:async';
import 'package:dio/dio.dart';
import '../models/effect.dart';

// ============================================================================
// LED Control Service - HTTP communication with ESP32
// ============================================================================
// Handles LED control via REST API over WiFi/AP connection

class LEDControlService {
  final Dio _dio;
  String _baseUrl;
  Timer? _debounceTimer;
  Timer? _brightnessThrottleTimer;
  int? _pendingBrightness;
  bool _brightnessThrottled = false;

  LEDControlService({String? baseUrl, Dio? dio})
    : _baseUrl = baseUrl ?? 'http://192.168.4.1',
      _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 5);
    _dio.options.receiveTimeout = const Duration(seconds: 5);
  }

  /// Set base URL (AP: 192.168.4.1, WiFi: device IP)
  void setBaseUrl(String url) {
    _baseUrl = url;
  }

  // ========================================================================
  // Status & Effects List
  // ========================================================================

  /// Get current LED status
  Future<LEDStatus> getStatus() async {
    final response = await _dio.get('$_baseUrl/api/led/status');
    return LEDStatus.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get list of all effects
  Future<List<Effect>> getEffects() async {
    final response = await _dio.get('$_baseUrl/api/led/effects');
    final list = response.data as List<dynamic>;
    return list
        .map((json) => Effect.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get current effect parameters
  Future<Map<String, dynamic>> getParams() async {
    final response = await _dio.get('$_baseUrl/api/led/params');
    return response.data as Map<String, dynamic>;
  }

  // ========================================================================
  // Control Methods
  // ========================================================================

  /// Set current effect by ID
  Future<void> setEffect(int effectId) async {
    await _dio.post('$_baseUrl/api/led/effect', data: {'id': effectId});
  }

  /// Set power on/off
  Future<void> setPower(bool on) async {
    await _dio.post('$_baseUrl/api/led/power', data: {'on': on});
  }

  /// Set global brightness (0-255), optionally saving to NVS
  Future<void> setBrightness(int value, {bool save = false}) async {
    await _dio.post(
      '$_baseUrl/api/led/brightness',
      data: {'value': value, 'save': save},
    );
  }

  /// Set brightness and save to NVS (for when user finishes adjusting)
  Future<void> setBrightnessFinal(int value) async {
    await setBrightness(value, save: true);
  }

  /// Set brightness with throttle for slider (smooth live updates)
  /// Sends immediately if not throttled, then limits to every 50ms
  void setBrightnessThrottled(int value) {
    _pendingBrightness = value;

    if (!_brightnessThrottled) {
      // Send immediately
      _brightnessThrottled = true;
      setBrightness(value);

      // Set up throttle cooldown
      _brightnessThrottleTimer?.cancel();
      _brightnessThrottleTimer = Timer(const Duration(milliseconds: 50), () {
        _brightnessThrottled = false;
        // Send any pending value that came during cooldown
        if (_pendingBrightness != null && _pendingBrightness != value) {
          setBrightness(_pendingBrightness!);
        }
      });
    }
  }

  /// Legacy debounced method - still useful for other cases
  void setBrightnessDebounced(
    int value, {
    Duration delay = const Duration(milliseconds: 50),
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () => setBrightness(value));
  }

  /// Update effect parameters
  Future<void> setParams(Map<String, dynamic> params) async {
    await _dio.post('$_baseUrl/api/led/params', data: params);
  }

  /// Set single parameter with debounce (for sliders)
  void setParamDebounced(
    String key,
    dynamic value, {
    Duration delay = const Duration(milliseconds: 50),
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () => setParams({key: value}));
  }

  // ========================================================================
  // Connection Check
  // ========================================================================

  /// Check if device is reachable
  Future<bool> isConnected() async {
    try {
      await _dio.get(
        '$_baseUrl/api/led/status',
        options: Options(receiveTimeout: const Duration(seconds: 2)),
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _debounceTimer?.cancel();
    _dio.close();
  }
}

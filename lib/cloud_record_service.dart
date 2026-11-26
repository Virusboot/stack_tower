import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'security.dart';

/// Lightweight, 100% crash-free background sync service for Worldwide Record.
/// Uses native Dart core HttpClient with zero UI blocking and silent error-handling.
class CloudRecordService {
  static const String _kFirebaseUrl =
      'https://stack-tower-8766e-default-rtdb.firebaseio.com/world_record.json';

  /// Fetches the latest global world record from Firebase Cloud.
  /// Silently times out after 3 seconds if offline.
  static Future<int?> fetchWorldRecord() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final request = await client.getUrl(Uri.parse(_kFirebaseUrl));
      final response = await request.close().timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final dynamic data = json.decode(body);
        if (data is int && data > 0) {
          debugPrint('[CloudRecord] Live world record fetched: $data');
          // Cache locally securely
          await SecurityService.saveSecureWorldRecord(data);
          return data;
        } else if (data is num && data > 0) {
          final int val = data.toInt();
          await SecurityService.saveSecureWorldRecord(val);
          return val;
        }
      }
    } catch (e) {
      debugPrint('[CloudRecord] Silent fallback to local record (offline/timeout): $e');
    } finally {
      client?.close(force: true);
    }
    return null;
  }

  /// Submits the new world record to Firebase Cloud so ALL users worldwide see it.
  static Future<void> submitNewRecord(int newScore) async {
    if (newScore <= SecurityService.kInitialWorldRecord) return;

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final request = await client.putUrl(Uri.parse(_kFirebaseUrl));
      request.headers.contentType = ContentType.json;
      request.write('$newScore');

      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        debugPrint('[CloudRecord] New world record $newScore successfully published to cloud!');
      }
    } catch (e) {
      debugPrint('[CloudRecord] Error publishing record to cloud: $e');
    } finally {
      client?.close(force: true);
    }
  }
}

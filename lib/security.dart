import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cryptographic and in-memory security service to prevent score tampering,
/// memory inspection, and save-file hacking.
class SecurityService {
  static const String _scoreKey = 'st_secure_pb';
  static const String _hashKey = 'st_secure_sig';
  static const String _worldKey = 'st_secure_wr';
  static const String _worldHashKey = 'st_secure_wr_sig';
  static const String _salt = 'StackTower_AntiTamper_v1_Salt982741!';

  // Baseline global record starts at 0
  static const int kInitialWorldRecord = 0;

  /// Lightweight, deterministic hash function (FNV-1a 64-bit variant)
  /// ensuring 100% offline verification without third-party dependencies.
  static String _generateSignature(int value, String keyType) {
    final String raw = '$value:$_salt:$keyType:SecureStackTower';
    final List<int> bytes = utf8.encode(raw);
    int hash = 0xcbf29ce484222325;
    for (final int b in bytes) {
      hash ^= b;
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  /// Securely reads and verifies the player's personal best score.
  /// If the XML was tampered with, the signature will not match and
  /// the score will safely reset to 0.
  static Future<int> getSecureBestScore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final int? stored = p.getInt(_scoreKey);
      final String? sig = p.getString(_hashKey);

      if (stored == null || sig == null) {
        // Fallback check for legacy unencrypted score
        final int legacy = p.getInt('best') ?? 0;
        if (legacy > 0) {
          await saveSecureBestScore(legacy);
          return legacy;
        }
        return 0;
      }

      final String expectedSig = _generateSignature(stored, 'pb');
      if (sig == expectedSig && stored >= 0 && stored < 100000) {
        return stored;
      } else {
        debugPrint('[Security] Tampering detected in save data! Resetting score.');
        await saveSecureBestScore(0);
        return 0;
      }
    } catch (e) {
      debugPrint('[Security] Error reading secure score: $e');
      return 0;
    }
  }

  /// Securely saves the personal best score with anti-tamper signature.
  static Future<void> saveSecureBestScore(int score) async {
    try {
      final p = await SharedPreferences.getInstance();
      final String sig = _generateSignature(score, 'pb');
      await p.setInt(_scoreKey, score);
      await p.setString(_hashKey, sig);
      await p.setInt('best', score); // Mirror for legacy compatibility
    } catch (e) {
      debugPrint('[Security] Error saving secure score: $e');
    }
  }

  /// Securely reads and verifies the global/world record benchmark.
  static Future<int> getSecureWorldRecord() async {
    try {
      final p = await SharedPreferences.getInstance();
      final int? stored = p.getInt(_worldKey);
      final String? sig = p.getString(_worldHashKey);

      if (stored == null || sig == null) {
        await saveSecureWorldRecord(kInitialWorldRecord);
        return kInitialWorldRecord;
      }

      final String expectedSig = _generateSignature(stored, 'wr');
      if (sig == expectedSig && stored >= 0 && stored < 100000) {
        return stored;
      } else {
        await saveSecureWorldRecord(kInitialWorldRecord);
        return kInitialWorldRecord;
      }
    } catch (e) {
      return kInitialWorldRecord;
    }
  }

  /// Securely saves the world record when a player sets a new record.
  static Future<void> saveSecureWorldRecord(int record) async {
    try {
      final p = await SharedPreferences.getInstance();
      final String sig = _generateSignature(record, 'wr');
      await p.setInt(_worldKey, record);
      await p.setString(_worldHashKey, sig);
    } catch (e) {
      debugPrint('[Security] Error saving world record: $e');
    }
  }
}

/// In-memory obfuscated integer to foil memory scanners (GameGuardian, CheatEngine).
/// The stored value and bitmask randomly mutate upon every single write,
/// making static memory address searches completely ineffective.
class ObfuscatedScore {
  int _mask = 0;
  int _maskedValue = 0;
  final Random _rng = Random();

  ObfuscatedScore([int initial = 0]) {
    set(initial);
  }

  int get value => _maskedValue ^ _mask;

  void set(int val) {
    _mask = _rng.nextInt(0x3FFFFFFF);
    _maskedValue = val ^ _mask;
  }

  void increment() {
    final int current = value;
    set(current + 1);
  }
}

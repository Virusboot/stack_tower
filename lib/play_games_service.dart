import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'security.dart';

/// Service managing Google Play Games Services:
/// - Silent / automatic sign-in on app start
/// - Fetching the single #1 World Record holder and score
/// - Submitting new player high scores safely
/// - Native Leaderboards overlay
class PlayGamesService {
  // Google Play Console Leaderboard ID
  // (Set in Google Play Console > Play Games Services > Leaderboards)
  static const String kAndroidLeaderboardId =
      'leaderboard_stack_tower_world_record';

  static const String _kCachedHolderKey = 'st_wr_holder_name';

  static bool _isSignedIn = false;
  static bool get isSignedIn => _isSignedIn;

  static String? _topPlayerName;
  static int? _topPlayerScore;

  static String? get topPlayerName => _topPlayerName;
  static int? get topPlayerScore => _topPlayerScore;

  /// Initializes Play Games, restores cached world champion name,
  /// and silently signs in in the background.
  static Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      _topPlayerName = p.getString(_kCachedHolderKey);
      _topPlayerScore = await SecurityService.getSecureWorldRecord();

      // Silent sign in attempt
      final res = await GameAuth.signIn();
      _isSignedIn = (res != null);
      if (_isSignedIn) {
        debugPrint('[PlayGames] Successfully signed in to Google Play Games.');
        await fetchWorldRecord();
      }
    } catch (e) {
      debugPrint('[PlayGames] Silent sign-in skipped (normal if offline or pending Play Console setup): $e');
      _isSignedIn = false;
    }
  }

  /// Explicit sign-in trigger (e.g. when user taps the World Record badge)
  static Future<bool> manualSignIn() async {
    try {
      final res = await GameAuth.signIn();
      _isSignedIn = (res != null);
      if (_isSignedIn) {
        await fetchWorldRecord();
      }
      return _isSignedIn;
    } catch (e) {
      debugPrint('[PlayGames] Manual sign-in error: $e');
      return false;
    }
  }

  /// Fetches ONLY the #1 World Record holder from Google Play Games Leaderboard
  static Future<Map<String, dynamic>?> fetchWorldRecord() async {
    try {
      final scores = await Leaderboards.loadLeaderboardScores(
        androidLeaderboardID: kAndroidLeaderboardId,
        scope: PlayerScope.global,
        timeScope: TimeScope.allTime,
        maxResults: 1, // Exactly 1 person (World Record holder)
        forceRefresh: true,
      );

      if (scores != null && scores.isNotEmpty) {
        final top = scores.first;
        _topPlayerScore = top.rawScore;
        _topPlayerName = top.scoreHolder.displayName;

        debugPrint('[PlayGames] Fetched #1 World Champion: $_topPlayerName ($topPlayerScore)');

        // Securely cache locally so it works even offline
        if (_topPlayerScore != null && _topPlayerScore! >= SecurityService.kInitialWorldRecord) {
          await SecurityService.saveSecureWorldRecord(_topPlayerScore!);
        }
        if (_topPlayerName != null && _topPlayerName!.trim().isNotEmpty) {
          final p = await SharedPreferences.getInstance();
          await p.setString(_kCachedHolderKey, _topPlayerName!);
        }

        return {
          'score': _topPlayerScore,
          'name': _topPlayerName,
        };
      }
    } catch (e) {
      debugPrint('[PlayGames] Leaderboard fetch note: $e');
    }
    return null;
  }

  /// Submits the player's score to Google Play Games
  static Future<void> submitScore(int score) async {
    if (score <= 0) return;
    try {
      if (!_isSignedIn) {
        await manualSignIn();
      }
      if (_isSignedIn) {
        await Leaderboards.submitScore(
          score: Score(
            androidLeaderboardID: kAndroidLeaderboardId,
            value: score,
          ),
        );
        debugPrint('[PlayGames] Score $score submitted to Google Play Games.');
        // Refresh world record
        await fetchWorldRecord();
      }
    } catch (e) {
      debugPrint('[PlayGames] Error submitting score: $e');
    }
  }

  /// Displays the native Google Play Games Leaderboard overlay
  static Future<void> showLeaderboards() async {
    try {
      if (!_isSignedIn) {
        final ok = await manualSignIn();
        if (!ok) return;
      }
      await Leaderboards.showLeaderboards(
        androidLeaderboardID: kAndroidLeaderboardId,
      );
    } catch (e) {
      debugPrint('[PlayGames] Error showing leaderboards: $e');
    }
  }
}

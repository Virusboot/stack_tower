import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// ====== REAL ADMOB IDs FOR PRODUCTION ======
const String kRealBannerId = 'ca-app-pub-6236208130146050/4185598419';
const String kRealInterstitialId = 'ca-app-pub-6236208130146050/1176291697';
// Rewarded ad unit ID (Fallback to Google verified test ID if unit not yet created in AdMob console)
const String kRealRewardedId = 'ca-app-pub-3940256099942544/5224354917';
/// ==========================================

const String _testBannerId = 'ca-app-pub-3940256099942544/6300978111';
const String _testInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
const String _testRewardedId = 'ca-app-pub-3940256099942544/5224354917';

class AdService {
  static String get bannerId => kDebugMode ? _testBannerId : kRealBannerId;
  static String get interstitialId =>
      kDebugMode ? _testInterstitialId : kRealInterstitialId;
  static String get rewardedId =>
      kDebugMode ? _testRewardedId : kRealRewardedId;

  static InterstitialAd? _inter;
  static RewardedAd? _rewarded;
  static bool _isLoadingRewarded = false;
  static DateTime _lastInterstitialTime =
      DateTime.fromMillisecondsSinceEpoch(0);
  static Future<InitializationStatus>? _initFuture;

  static Future<void> init() async {
    try {
      _initFuture ??= MobileAds.instance.initialize();
      await _initFuture;
      _loadInterstitial();
      _loadRewarded();
    } catch (e) {
      debugPrint('[AdService] Init error: $e');
    }
  }

  // ==================== INTERSTITIAL ADS ====================
  static void _loadInterstitial() {
    try {
      InterstitialAd.load(
        adUnitId: interstitialId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) => _inter = ad,
          onAdFailedToLoad: (error) {
            debugPrint('[AdService] Interstitial load failed: $error');
            _inter = null;
          },
        ),
      );
    } catch (e) {
      debugPrint('[AdService] Interstitial load error: $e');
      _inter = null;
    }
  }

  /// Policy-safe interstitial display with 40-second cooldown
  static void showInterstitial({VoidCallback? onComplete}) {
    try {
      final now = DateTime.now();
      if (now.difference(_lastInterstitialTime).inSeconds < 40) {
        onComplete?.call();
        return;
      }

      final ad = _inter;
      if (ad == null) {
        _loadInterstitial();
        onComplete?.call();
        return;
      }

      _lastInterstitialTime = now;
      _inter = null;
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (a) {
          try {
            a.dispose();
          } catch (_) {}
          _loadInterstitial();
          onComplete?.call();
        },
        onAdFailedToShowFullScreenContent: (a, error) {
          debugPrint('[AdService] Interstitial show failed: $error');
          try {
            a.dispose();
          } catch (_) {}
          _loadInterstitial();
          onComplete?.call();
        },
      );
      ad.show();
    } catch (e) {
      debugPrint('[AdService] Error showing interstitial: $e');
      onComplete?.call();
    }
  }

  // ==================== REWARDED ADS (MAX REVENUE) ====================
  static bool get isRewardedAvailable => _rewarded != null;

  static void _loadRewarded() {
    if (_isLoadingRewarded || _rewarded != null) return;
    _isLoadingRewarded = true;

    try {
      RewardedAd.load(
        adUnitId: rewardedId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewarded = ad;
            _isLoadingRewarded = false;
          },
          onAdFailedToLoad: (error) {
            debugPrint('[AdService] Rewarded ad failed to load: $error');
            _rewarded = null;
            _isLoadingRewarded = false;
          },
        ),
      );
    } catch (e) {
      debugPrint('[AdService] Rewarded ad load error: $e');
      _rewarded = null;
      _isLoadingRewarded = false;
    }
  }

  /// Shows Rewarded Video ad to grant player a game revive.
  /// Generates highest eCPM with 100% user-opt-in policy safety.
  static void showRewardedAd({
    required VoidCallback onRewardEarned,
    VoidCallback? onDismissed,
  }) {
    final ad = _rewarded;
    if (ad == null) {
      _loadRewarded();
      onDismissed?.call();
      return;
    }

    _rewarded = null;
    bool rewardGranted = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        try {
          a.dispose();
        } catch (_) {}
        _loadRewarded();
        if (rewardGranted) {
          onRewardEarned();
        } else {
          onDismissed?.call();
        }
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        debugPrint('[AdService] Rewarded ad show failed: $error');
        try {
          a.dispose();
        } catch (_) {}
        _loadRewarded();
        onDismissed?.call();
      },
    );

    ad.show(
      onUserEarnedReward: (AdWithoutView adView, RewardItem reward) {
        rewardGranted = true;
      },
    );
  }
}

// ==================== BANNER AD CONTAINER ====================
class BannerBox extends StatefulWidget {
  const BannerBox({super.key});

  @override
  State<BannerBox> createState() => _BannerBoxState();
}

class _BannerBoxState extends State<BannerBox> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  Future<void> _loadBanner() async {
    try {
      await AdService.init();
      if (!mounted) return;

      final banner = BannerAd(
        adUnitId: AdService.bannerId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            if (mounted) setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('[AdService] BannerAd failed: $error');
            try {
              ad.dispose();
            } catch (_) {}
            if (mounted) {
              setState(() {
                _loaded = false;
                _ad = null;
              });
            }
          },
        ),
      );

      _ad = banner;
      await banner.load();
    } catch (e) {
      debugPrint('[AdService] BannerBox error: $e');
      if (mounted) {
        setState(() {
          _loaded = false;
          _ad = null;
        });
      }
    }
  }

  @override
  void dispose() {
    final adToDispose = _ad;
    _ad = null;
    try {
      adToDispose?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) {
      return const SizedBox.shrink();
    }
    return Container(
      alignment: Alignment.center,
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF0F1225).withAlpha(180),
        border: const Border(
          top: BorderSide(color: Colors.white12, width: 1),
        ),
      ),
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}

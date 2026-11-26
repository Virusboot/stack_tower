import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// ====== REAL ADMOB IDs FOR PRODUCTION (GOOGLE PLAY LINKED APP) ======
const String kRealBannerId = 'ca-app-pub-6236208130146050/9403132041';
const String kRealInterstitialId = 'ca-app-pub-6236208130146050/8473193757';
const String kRealRewardedId = 'ca-app-pub-3940256099942544/5224354917';
/// ======================================================================

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

  static bool _isLoadingInterstitial = false;
  static bool _isLoadingRewarded = false;
  static int _interstitialRetryCount = 0;
  static int _rewardedRetryCount = 0;
  static Timer? _interstitialRetryTimer;
  static Timer? _rewardedRetryTimer;

  static Future<InitializationStatus>? _initFuture;

  static Future<void> init() async {
    try {
      _initFuture ??= MobileAds.instance.initialize();
      await _initFuture;
      prepareInterstitial();
      _loadRewarded();
    } catch (e) {
      debugPrint('[AdService] Init error: $e');
    }
  }

  // ==================== INTERSTITIAL ADS ====================
  static bool get isInterstitialLoaded => _inter != null;

  static void prepareInterstitial() {
    if (_inter != null || _isLoadingInterstitial) return;
    _isLoadingInterstitial = true;

    try {
      InterstitialAd.load(
        adUnitId: interstitialId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            debugPrint('[AdService] Interstitial successfully loaded and cached.');
            _inter = ad;
            _isLoadingInterstitial = false;
            _interstitialRetryCount = 0;
            _interstitialRetryTimer?.cancel();
          },
          onAdFailedToLoad: (error) {
            debugPrint('[AdService] Interstitial failed to load: $error');
            _inter = null;
            _isLoadingInterstitial = false;

            // Exponential backoff auto-retry (e.g. 4s, 8s, 16s, max 30s)
            _interstitialRetryCount++;
            final delaySec = min(30, max(4, 2 << _interstitialRetryCount));
            _interstitialRetryTimer?.cancel();
            _interstitialRetryTimer = Timer(Duration(seconds: delaySec), () {
              prepareInterstitial();
            });
          },
        ),
      );
    } catch (e) {
      debugPrint('[AdService] Interstitial load error: $e');
      _inter = null;
      _isLoadingInterstitial = false;
    }
  }

  /// Policy-safe display of cached interstitial ad.
  /// Calls onComplete immediately once ad is dismissed or failed.
  static void showInterstitial({VoidCallback? onComplete}) {
    final ad = _inter;
    if (ad == null) {
      prepareInterstitial();
      onComplete?.call();
      return;
    }

    _inter = null;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        try {
          a.dispose();
        } catch (_) {}
        prepareInterstitial(); // Immediately preload next ad for the next cycle
        onComplete?.call();
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        debugPrint('[AdService] Interstitial failed to show: $error');
        try {
          a.dispose();
        } catch (_) {}
        prepareInterstitial();
        onComplete?.call();
      },
    );

    try {
      ad.show();
    } catch (e) {
      debugPrint('[AdService] Error showing interstitial: $e');
      prepareInterstitial();
      onComplete?.call();
    }
  }

  // ==================== REWARDED ADS (REVIVE FEATURE) ====================
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
            debugPrint('[AdService] Rewarded ad successfully loaded.');
            _rewarded = ad;
            _isLoadingRewarded = false;
            _rewardedRetryCount = 0;
            _rewardedRetryTimer?.cancel();
          },
          onAdFailedToLoad: (error) {
            debugPrint('[AdService] Rewarded ad load failed: $error');
            _rewarded = null;
            _isLoadingRewarded = false;

            // Auto-retry rewarded ad load
            _rewardedRetryCount++;
            final delaySec = min(30, max(5, 2 << _rewardedRetryCount));
            _rewardedRetryTimer?.cancel();
            _rewardedRetryTimer = Timer(Duration(seconds: delaySec), () {
              _loadRewarded();
            });
          },
        ),
      );
    } catch (e) {
      debugPrint('[AdService] Rewarded ad load error: $e');
      _rewarded = null;
      _isLoadingRewarded = false;
    }
  }

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

    try {
      ad.show(
        onUserEarnedReward: (AdWithoutView adView, RewardItem reward) {
          rewardGranted = true;
        },
      );
    } catch (e) {
      debugPrint('[AdService] Error showing rewarded ad: $e');
      _loadRewarded();
      onDismissed?.call();
    }
  }
}

// ==================== BANNER AD CONTAINER (AUTO-RETRY & ADAPTIVE) ====================
class BannerBox extends StatefulWidget {
  const BannerBox({super.key});

  @override
  State<BannerBox> createState() => _BannerBoxState();
}

class _BannerBoxState extends State<BannerBox> {
  BannerAd? _ad;
  bool _loaded = false;
  Timer? _retryTimer;
  int _retryCount = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  Future<void> _loadBanner() async {
    if (_isLoading || !mounted) return;
    _isLoading = true;

    try {
      await AdService.init();
      if (!mounted) {
        _isLoading = false;
        return;
      }

      // Safe clean up of previous ad instance before requesting new one
      final oldAd = _ad;
      _ad = null;
      try {
        oldAd?.dispose();
      } catch (_) {}

      final banner = BannerAd(
        adUnitId: AdService.bannerId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            debugPrint('[AdService] Banner successfully loaded.');
            if (mounted) {
              setState(() {
                _loaded = true;
                _ad = ad as BannerAd;
                _isLoading = false;
                _retryCount = 0;
              });
              _retryTimer?.cancel();
            }
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('[AdService] BannerAd failed to load: $error');
            try {
              ad.dispose();
            } catch (_) {}
            if (mounted) {
              setState(() {
                _loaded = false;
                _ad = null;
                _isLoading = false;
              });

              // Auto-retry banner loading every 6 to 15 seconds so phone NEVER stays without ads
              _retryCount++;
              final delaySec = min(20, max(5, _retryCount * 4));
              _retryTimer?.cancel();
              _retryTimer = Timer(Duration(seconds: delaySec), () {
                if (mounted) _loadBanner();
              });
            }
          },
        ),
      );

      await banner.load();
    } catch (e) {
      debugPrint('[AdService] BannerBox exception: $e');
      _isLoading = false;
      if (mounted) {
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(seconds: 10), () {
          if (mounted) _loadBanner();
        });
      }
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
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
      // Sleek transparent placeholder so screen layout doesn't jump
      return const SizedBox(height: 52);
    }

    return Container(
      alignment: Alignment.center,
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF0F1225).withAlpha(190),
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

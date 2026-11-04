import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// ====== PLAY STORE SE PEHLE YAHAN APNI REAL ADMOB IDs DAALO ======
/// Debug mode (flutter run) me hamesha Google ke TEST ads chalte hain.
/// Release build (Play Store wali) me neeche ki real IDs use hoti hain.
const String kRealBannerId = 'ca-app-pub-6236208130146050/4185598419';
const String kRealInterstitialId = 'ca-app-pub-6236208130146050/1176291697';
/// ================================================================

const String _testBannerId = 'ca-app-pub-3940256099942544/6300978111';
const String _testInterstitialId = 'ca-app-pub-3940256099942544/1033173712';

class AdService {
  static String get bannerId => kDebugMode ? _testBannerId : kRealBannerId;
  static String get interstitialId =>
      kDebugMode ? _testInterstitialId : kRealInterstitialId;

  static InterstitialAd? _inter;
  static DateTime _lastInterstitialTime =
      DateTime.fromMillisecondsSinceEpoch(0);
  static Future<InitializationStatus>? _initFuture;

  static Future<void> init() async {
    try {
      _initFuture ??= MobileAds.instance.initialize();
      await _initFuture;
      _load();
    } catch (e) {
      debugPrint('Ads init failed gracefully: $e');
    }
  }

  static void _load() {
    try {
      InterstitialAd.load(
        adUnitId: interstitialId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) => _inter = ad,
          onAdFailedToLoad: (error) {
            debugPrint('Interstitial failed to load: $error');
            _inter = null;
          },
        ),
      );
    } catch (e) {
      debugPrint('Error initiating interstitial load: $e');
      _inter = null;
    }
  }

  /// Policy-safe interstitial display:
  /// 1. Cooldown of 45 seconds to comply with Google Better Ads Standards.
  /// 2. onComplete callback so game does not run in background while ad is showing.
  static void showInterstitial({VoidCallback? onComplete}) {
    try {
      final now = DateTime.now();
      if (now.difference(_lastInterstitialTime).inSeconds < 45) {
        onComplete?.call();
        return;
      }

      final ad = _inter;
      if (ad == null) {
        _load();
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
          _load();
          onComplete?.call();
        },
        onAdFailedToShowFullScreenContent: (a, error) {
          debugPrint('Interstitial failed to show: $error');
          try {
            a.dispose();
          } catch (_) {}
          _load();
          onComplete?.call();
        },
      );
      ad.show();
    } catch (e) {
      debugPrint('Error showing interstitial: $e');
      onComplete?.call();
    }
  }
}

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
      // Ensure SDK initialization is complete before loading banner
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
            debugPrint('BannerAd failed to load: $error');
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
      debugPrint('BannerBox error: $e');
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
      width: ad.size.width.toDouble(),
      height: 50,
      child: AdWidget(ad: ad),
    );
  }
}

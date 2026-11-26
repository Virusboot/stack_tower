import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ads.dart';
import 'play_games_service.dart';
import 'security.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global safety handlers to guarantee zero unexpected crashes
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[CrashSafety] Flutter error: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[CrashSafety] Platform error caught: $error');
    return true; // Prevents crash propagation
  };

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Immersive Sticky mode: Hides Android bottom navigation bar and status bar
  // so game canvas and pieces NEVER slide or clip behind system buttons!
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF0F1225),
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  AdService.init();

  runApp(const MaterialApp(
    title: 'Stack Tower',
    debugShowCheckedModeBanner: false,
    home: StackGame(),
  ));
}

class Block {
  double x, w;
  Block(this.x, this.w);
}

class Piece {
  double x, worldY, w, vy;
  Color color;
  Piece(this.x, this.worldY, this.w, this.color) : vy = 0;
}

/// Visual theme definition for dynamic level progression
class GameTheme {
  final String name;
  final Color topColor;
  final Color bottomColor;
  final double hueShift;

  const GameTheme({
    required this.name,
    required this.topColor,
    required this.bottomColor,
    required this.hueShift,
  });
}

class StackGame extends StatefulWidget {
  const StackGame({super.key});

  @override
  State<StackGame> createState() => _StackGameState();
}

class _StackGameState extends State<StackGame>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double bh = 36; // Block height
  static const double bottomPad = 56;

  // 5 distinct arcade themes based on score milestones
  static const GameTheme themeLevel1 = GameTheme(
    name: 'Cosmic Indigo',
    topColor: Color(0xFF2B2F6B),
    bottomColor: Color(0xFF0F1230),
    hueShift: 0.0,
  );
  static const GameTheme themeLevel2 = GameTheme(
    name: 'Cyber Violet',
    topColor: Color(0xFF6B1B54),
    bottomColor: Color(0xFF1A0A26),
    hueShift: 75.0,
  );
  static const GameTheme themeLevel3 = GameTheme(
    name: 'Neon Emerald',
    topColor: Color(0xFF0D5C46),
    bottomColor: Color(0xFF06211C),
    hueShift: 160.0,
  );
  static const GameTheme themeLevel4 = GameTheme(
    name: 'Solar Blaze',
    topColor: Color(0xFF7A2D0D),
    bottomColor: Color(0xFF260D05),
    hueShift: 240.0,
  );
  static const GameTheme themeLevel5 = GameTheme(
    name: 'Mythic Gold',
    topColor: Color(0xFF382352),
    bottomColor: Color(0xFF0B0612),
    hueShift: 310.0,
  );

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  final List<Block> blocks = [];
  final List<Piece> pieces = [];
  Size _size = Size.zero;

  // In-memory obfuscated score structure to prevent memory scanning
  final ObfuscatedScore _secureScore = ObfuscatedScore(0);
  int get score => _secureScore.value;

  double baseW = 0, curX = 0, curW = 0, dir = 1, cam = 0, flash = 0;
  int best = 0;
  int worldBest = SecurityService.kInitialWorldRecord;
  String? worldRecordHolder;
  int combo = 0;
  int gameOvers = 0;
  int _outsSinceLastAd = 0;
  bool over = false;
  bool soundOn = true;
  bool _isRestarting = false;
  bool _isExitDialogShowing = false;
  bool _revivedThisRun = false;
  bool _showingRevivePrompt = false;

  // Milestone banner animation
  String? _milestoneBanner;
  double _milestoneOpacity = 0.0;

  // Anti-cheat rate limiting
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _overAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Background smooth color interpolation
  Color _curTopColor = themeLevel1.topColor;
  Color _curBottomColor = themeLevel1.bottomColor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadScores();
    _ticker = createTicker(_tick)..start();
  }

  Future<void> _loadScores() async {
    final int b = await SecurityService.getSecureBestScore();
    final int wb = await SecurityService.getSecureWorldRecord();
    final p = await SharedPreferences.getInstance();

    // Initialize Google Play Games silent sign-in and fetch World Champion
    PlayGamesService.init().then((_) {
      if (mounted) {
        final holder = PlayGamesService.topPlayerName ?? p.getString('st_wr_holder_name');
        final pgsScore = PlayGamesService.topPlayerScore;
        setState(() {
          if (pgsScore != null && pgsScore >= worldBest) {
            worldBest = pgsScore;
          }
          if (holder != null && holder.isNotEmpty) {
            worldRecordHolder = holder;
          }
        });
      }
    });

    final String? cachedHolder = p.getString('st_wr_holder_name');

    if (!mounted) return;
    setState(() {
      best = b;
      worldBest = wb;
      worldRecordHolder = cachedHolder;
      soundOn = p.getBool('sound') ?? true;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_ticker.isActive) {
        _ticker.stop();
      }
    } else if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!_ticker.isActive && !over && !_showingRevivePrompt) {
        _last = Duration.zero;
        _ticker.start();
      }
    }
  }

  GameTheme _getThemeForScore(int currentScore) {
    if (currentScore >= 100) return themeLevel5;
    if (currentScore >= 75) return themeLevel4;
    if (currentScore >= 50) return themeLevel3;
    if (currentScore >= 30) return themeLevel2;
    return themeLevel1;
  }

  Color colorFor(int level) {
    final theme = _getThemeForScore(score);
    final double hue = (level * 10.0 + theme.hueShift) % 360.0;
    return HSVColor.fromAHSV(1, hue, 0.58, 0.95).toColor();
  }

  void _reset({bool fullReset = true}) {
    blocks.clear();
    pieces.clear();
    baseW = _size.width * 0.55;
    blocks.add(Block((_size.width - baseW) / 2, baseW));
    curW = baseW;
    curX = 0;
    dir = 1;
    if (fullReset) {
      _secureScore.set(0);
      _revivedThisRun = false;
    }
    combo = 0;
    cam = 0;
    over = false;
    _showingRevivePrompt = false;
    _milestoneBanner = null;
    _milestoneOpacity = 0.0;
  }

  void _tick(Duration elapsed) {
    final double dt =
        ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
    _last = elapsed;
    if (_size == Size.zero) return;

    if (!over && !_showingRevivePrompt) {
      final double speed = min(220.0 + score * 8.5, 620.0);
      curX += dir * speed * dt;
      final double maxX = _size.width - curW;
      if (curX > maxX) {
        curX = maxX;
        dir = -1;
      } else if (curX < 0) {
        curX = 0;
        dir = 1;
      }
    }

    final double target = max(0.0, (blocks.length - 6) * bh);
    cam += (target - cam) * min(1.0, dt * 6.0);

    for (final p in pieces) {
      p.vy += 1400.0 * dt;
      p.worldY -= p.vy * dt;
    }
    pieces.removeWhere((p) => p.worldY < cam - 400);
    flash = max(0.0, flash - dt * 3.0);

    // Smooth gradient color interpolation for dynamic themes
    final targetTheme = _getThemeForScore(score);
    _curTopColor = Color.lerp(_curTopColor, targetTheme.topColor, dt * 2.0) ??
        targetTheme.topColor;
    _curBottomColor =
        Color.lerp(_curBottomColor, targetTheme.bottomColor, dt * 2.0) ??
            targetTheme.bottomColor;

    // Fade milestone banner
    if (_milestoneOpacity > 0) {
      _milestoneOpacity = max(0.0, _milestoneOpacity - dt * 0.45);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _click() {
    if (soundOn) {
      try {
        SystemSound.play(SystemSoundType.click);
      } catch (_) {}
      try {
        HapticFeedback.selectionClick();
      } catch (_) {}
    }
  }

  void _onTap() {
    if (over || _showingRevivePrompt) {
      if (DateTime.now().difference(_overAt).inMilliseconds > 600) {
        _restart();
      }
      return;
    }

    if (blocks.isEmpty) return;

    // Anti-cheat rate limiting: physically impossible to drop faster than 120ms
    final now = DateTime.now();
    if (now.difference(_lastTapTime).inMilliseconds < 120) return;
    _lastTapTime = now;

    final top = blocks.last;
    final level = blocks.length;
    final double left = max(curX, top.x);
    final double right = min(curX + curW, top.x + top.w);
    final double overlap = right - left;

    // Complete miss
    if (overlap <= 0) {
      pieces.add(Piece(curX, level * bh, curW, colorFor(level)));
      _handleDefeat();
      return;
    }

    double nx, nw;
    if ((curX - top.x).abs() < 7) {
      // Perfect drop
      combo++;
      nx = top.x;
      nw = curW;
      if (combo >= 3) {
        nw = min(curW + 10.0, baseW);
        nx = max(0.0, min(nx - 5.0, _size.width - nw));
      }
      flash = 1;
      try {
        HapticFeedback.lightImpact();
      } catch (_) {}
    } else {
      combo = 0;
      nx = left;
      nw = overlap;
      if (curX < top.x) {
        pieces.add(Piece(curX, level * bh, top.x - curX, colorFor(level)));
      }
      if (curX + curW > top.x + top.w) {
        pieces.add(Piece(top.x + top.w, level * bh,
            curX + curW - (top.x + top.w), colorFor(level)));
      }
    }
    _click();

    blocks.add(Block(nx, nw));
    _secureScore.increment();
    curW = nw;
    dir = score.isEven ? 1 : -1;
    curX = dir == 1 ? 0 : _size.width - curW;

    // Check for milestone themes (30, 50, 75, 100)
    _checkMilestone();
  }

  void _checkMilestone() {
    String? banner;
    if (score == 30) {
      banner = '⚡ LEVEL UP! CYBER VIOLET THEME';
    } else if (score == 50) {
      banner = '🌟 LEVEL UP! NEON EMERALD THEME';
    } else if (score == 75) {
      banner = '🔥 LEVEL UP! SOLAR BLAZE THEME';
    } else if (score == 100) {
      banner = '👑 LEVEL UP! MYTHIC GOLD THEME';
    }

    if (banner != null) {
      _milestoneBanner = banner;
      _milestoneOpacity = 1.0;
      try {
        HapticFeedback.heavyImpact();
      } catch (_) {}
    }
  }

  void _handleDefeat() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    // Check if player qualifies for a Rewarded Ad Revive
    if (!_revivedThisRun && score >= 5 && AdService.isRewardedAvailable) {
      setState(() {
        _showingRevivePrompt = true;
      });
      return;
    }

    _finalizeGameOver();
  }

  void _finalizeGameOver() {
    over = true;
    _showingRevivePrompt = false;
    _overAt = DateTime.now();
    gameOvers++;
    _outsSinceLastAd++;

    // Update Personal Best securely
    if (score > best) {
      best = score;
      SecurityService.saveSecureBestScore(best);
    }

    // Submit score to Google Play Games Leaderboard
    PlayGamesService.submitScore(score);

    // Update Worldwide Record securely if beaten
    if (score > worldBest) {
      worldBest = score;
      worldRecordHolder = 'You';
      SecurityService.saveSecureWorldRecord(worldBest);
    }

    setState(() {});
  }

  void _onReviveWithAd() {
    AdService.showRewardedAd(
      onRewardEarned: () {
        if (!mounted) return;
        setState(() {
          _revivedThisRun = true;
          _showingRevivePrompt = false;
          // Spawn new block right above tower with matching width
          final top = blocks.last;
          curW = top.w;
          curX = top.x;
          combo = 0;
          flash = 1.0;
          _last = Duration.zero;
          _ticker.start();
        });
        try {
          HapticFeedback.mediumImpact();
        } catch (_) {}
      },
      onDismissed: () {
        if (mounted) {
          _finalizeGameOver();
        }
      },
    );
  }

  void _manualRestart() {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
    _reset(fullReset: true);
  }

  void _restart() {
    if (_isRestarting) return;
    _isRestarting = true;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    // Show interstitial every 3 outs. If ad is loaded, show it and reset counter.
    // If not ready yet, keep counter >= 3 and request ad so next death triggers it.
    if (_outsSinceLastAd >= 3) {
      if (AdService.isInterstitialLoaded) {
        AdService.showInterstitial(onComplete: () {
          _outsSinceLastAd = 0;
          if (mounted) {
            _reset(fullReset: true);
            _isRestarting = false;
          }
        });
        return;
      } else {
        AdService.prepareInterstitial();
      }
    }

    _reset(fullReset: true);
    _isRestarting = false;
  }

  Future<void> _toggleSound() async {
    if (!mounted) return;
    setState(() => soundOn = !soundOn);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('sound', soundOn);
    } catch (_) {}
  }

  void _showLegalInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191E3B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white24, width: 1.2),
        ),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.amberAccent, size: 26),
            SizedBox(width: 10),
            Text('Stack Tower',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Official Terms of Service & Privacy Policy are hosted securely on our GitHub repository.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Terms of Service: virusboot.github.io/stack_tower/terms_and_conditions.html',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                  SizedBox(height: 6),
                  Text('• Privacy Policy: virusboot.github.io/stack_tower/privacy_policy.html',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                  SizedBox(height: 6),
                  Text('• Version: 1.0.8 (Build 9)',
                      style: TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK',
                style: TextStyle(
                    color: Colors.amberAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isExitDialogShowing) return;
        _isExitDialogShowing = true;
        try {
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1B1F3B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.white24),
              ),
              title: const Text('Exit Game?',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              content: const Text('Are you sure you want to exit Stack Tower?',
                  style: TextStyle(color: Colors.white70)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.amberAccent)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Exit',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          );
          if (shouldExit ?? false) {
            SystemNavigator.pop();
          }
        } catch (_) {
        } finally {
          _isExitDialogShowing = false;
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1225),
        // SafeArea prevents game or banner from sliding under default Android buttons
        body: SafeArea(
          top: false,
          bottom: true,
          maintainBottomViewPadding: true,
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final s = Size(c.maxWidth, c.maxHeight);
                  if (_size != s) {
                    final shouldReset = (_size == Size.zero || blocks.isEmpty);
                    _size = s;
                    if (shouldReset && s.width > 0 && s.height > 0) {
                      _reset(fullReset: true);
                    }
                  }
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (_) => _onTap(),
                          child: CustomPaint(
                            painter: _Painter(
                              g: this,
                              topColor: _curTopColor,
                              bottomColor: _curBottomColor,
                            ),
                          ),
                        ),
                      ),

                      // TOP HUD: Live Score + Dual Score Badges (Personal Best & Worldwide Record)
                      IgnorePointer(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('$score',
                                    style: const TextStyle(
                                        fontSize: 68,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -1.0,
                                        color: Colors.white,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black54,
                                            blurRadius: 16,
                                            offset: Offset(0, 4),
                                          )
                                        ])),
                                const SizedBox(height: 2),

                                // DUAL SCORE DISPLAY: SELF BEST & WORLD RECORD
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(110),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: Colors.white24, width: 0.8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Player Best
                                      Row(
                                        children: [
                                          const Icon(Icons.person_outline,
                                              size: 14, color: Colors.white70),
                                          const SizedBox(width: 4),
                                          Text('MY BEST $best',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white)),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                          width: 1,
                                          height: 14,
                                          color: Colors.white24),
                                      const SizedBox(width: 12),
                                      // Worldwide Record (Tap to view Google Play Games Leaderboard)
                                      GestureDetector(
                                        onTap: () => PlayGamesService.showLeaderboards(),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.public,
                                                size: 14, color: Colors.amberAccent),
                                            const SizedBox(width: 4),
                                            Text(
                                                worldRecordHolder != null && worldRecordHolder!.isNotEmpty
                                                    ? 'WORLD $worldBest ($worldRecordHolder)'
                                                    : 'WORLD $worldBest',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.amberAccent)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                if (combo >= 2) ...[
                                  const SizedBox(height: 6),
                                  Text('PERFECT x$combo',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.2,
                                          color: Colors.amberAccent)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),

                      // MILESTONE THEME BANNER (Triggers at 30, 50, 75, 100)
                      if (_milestoneBanner != null && _milestoneOpacity > 0)
                        IgnorePointer(
                          child: Align(
                            alignment: const Alignment(0, -0.22),
                            child: Opacity(
                              opacity: _milestoneOpacity,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.amberAccent.withAlpha(160),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    )
                                  ],
                                ),
                                child: Text(
                                  _milestoneBanner!,
                                  style: const TextStyle(
                                      color: Color(0xFF0F1225),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.1),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // TOP CONTROLS (Restart, Legal/Policy, Sound)
                      Positioned(
                        top: 24,
                        left: 14,
                        right: 14,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Restart Button
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(24),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.refresh_rounded,
                                    color: Colors.white, size: 22),
                                tooltip: 'Restart Game',
                                onPressed: _manualRestart,
                              ),
                            ),

                            // Right controls: Legal info & Sound
                            Row(
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(24),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.info_outline_rounded,
                                        color: Colors.white70, size: 22),
                                    tooltip: 'Terms & Privacy',
                                    onPressed: _showLegalInfoDialog,
                                  ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(24),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      soundOn
                                          ? Icons.volume_up_rounded
                                          : Icons.volume_off_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                    tooltip: soundOn ? 'Mute' : 'Unmute',
                                    onPressed: _toggleSound,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      if (score == 0 && !over && !_showingRevivePrompt)
                        const IgnorePointer(
                          child: Align(
                            alignment: Alignment(0, 0.52),
                            child: Text('TAP to drop the block',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70)),
                          ),
                        ),

                      // REWARDED AD: SECOND CHANCE / REVIVE MODAL (MAX REVENUE)
                      if (_showingRevivePrompt)
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 24),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F1225).withAlpha(245),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color: Colors.amberAccent.withAlpha(160),
                                  width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(180),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.play_circle_fill_rounded,
                                    color: Colors.amberAccent, size: 48),
                                const SizedBox(height: 8),
                                const Text('SECOND CHANCE?',
                                    style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.5,
                                        color: Colors.white)),
                                const SizedBox(height: 8),
                                Text(
                                  'Current Score: $score\nWatch an ad to continue your streak!',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 14),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: _onReviveWithAd,
                                  icon: const Icon(Icons.videocam_rounded,
                                      color: Color(0xFF0F1225), size: 22),
                                  label: const Text(
                                    'REVIVE NOW',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.1,
                                        color: Color(0xFF0F1225)),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amberAccent,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 28, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    elevation: 6,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextButton(
                                  onPressed: _finalizeGameOver,
                                  child: const Text('No thanks, end game',
                                      style: TextStyle(
                                          color: Colors.white54, fontSize: 13)),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // GAME OVER MODAL (DUAL SCORE & RECORD CELEBRATIONS)
                      if (over)
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 26),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 24),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F1225).withAlpha(245),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color: Colors.white24, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(180),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('GAME OVER',
                                    style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2.0,
                                        color: Colors.white)),
                                const SizedBox(height: 12),

                                // Record Celebration Badges
                                if (score >= worldBest)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.amberAccent,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Text(
                                      '🏆 NEW WORLD RECORD!',
                                      style: TextStyle(
                                          color: Color(0xFF0F1225),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900),
                                    ),
                                  )
                                else if (score >= best && score > 0)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF60A5FA),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Text(
                                      '⭐ NEW PERSONAL BEST!',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900),
                                    ),
                                  ),

                                // Stat Cards: Score, My Best, World Best
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(16),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      Column(
                                        children: [
                                          const Text('SCORE',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white60,
                                                  fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          Text('$score',
                                              style: const TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white)),
                                        ],
                                      ),
                                      Container(
                                          width: 1,
                                          height: 30,
                                          color: Colors.white24),
                                      Column(
                                        children: [
                                          const Text('MY BEST',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF60A5FA),
                                                  fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          Text('$best',
                                              style: const TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF60A5FA))),
                                        ],
                                      ),
                                      Container(
                                          width: 1,
                                          height: 30,
                                          color: Colors.white24),
                                      GestureDetector(
                                        onTap: () => PlayGamesService.showLeaderboards(),
                                        child: Column(
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.emoji_events,
                                                    size: 12, color: Colors.amberAccent),
                                                const SizedBox(width: 3),
                                                Text(
                                                    worldRecordHolder != null && worldRecordHolder!.isNotEmpty
                                                        ? 'WORLD (#1 $worldRecordHolder)'
                                                        : 'WORLD',
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.amberAccent,
                                                        fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text('$worldBest',
                                                style: const TextStyle(
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.amberAccent)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Prominent Play Again Button
                                ElevatedButton.icon(
                                  onPressed: _restart,
                                  icon: const Icon(Icons.replay_rounded,
                                      color: Color(0xFF0F1225), size: 22),
                                  label: const Text(
                                    'PLAY AGAIN',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.2,
                                        color: Color(0xFF0F1225)),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amberAccent,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 32, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                    elevation: 8,
                                    shadowColor:
                                        Colors.amberAccent.withAlpha(128),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                }),
              ),

              // Bottom Banner Ad: Safe, isolated, no overlap with buttons or game
              const BannerBox(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  final _StackGameState g;
  final Color topColor;
  final Color bottomColor;

  _Painter({
    required this.g,
    required this.topColor,
    required this.bottomColor,
  });

  double _sy(Size size, double worldY) =>
      size.height -
      _StackGameState.bottomPad -
      (worldY + _StackGameState.bh) +
      g.cam;

  void _rect(Canvas canvas, Size size, double x, double worldY, double w,
      Color color) {
    final double y = _sy(size, worldY);
    if (y > size.height || y + _StackGameState.bh < 0) return;
    canvas.drawRect(
        Rect.fromLTWH(x, y, w, _StackGameState.bh), Paint()..color = color);
    canvas.drawRect(Rect.fromLTWH(x, y, w, 5),
        Paint()..color = Colors.white.withAlpha(64));
    canvas.drawRect(Rect.fromLTWH(x, y + _StackGameState.bh - 4, w, 4),
        Paint()..color = Colors.black.withAlpha(46));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Strict clipping to ensure blocks never draw outside or behind system bars
    canvas.clipRect(Offset.zero & size);

    // Dynamic Level Theme background gradient
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [topColor, bottomColor],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    for (int i = 0; i < g.blocks.length; i++) {
      final b = g.blocks[i];
      _rect(canvas, size, b.x, i * _StackGameState.bh, b.w,
          g.colorFor(i));
    }
    if (!g.over && !g._showingRevivePrompt) {
      final int lvl = g.blocks.length;
      _rect(canvas, size, g.curX, lvl * _StackGameState.bh, g.curW,
          g.colorFor(lvl));
    }
    for (final p in g.pieces) {
      _rect(canvas, size, p.x, p.worldY, p.w, p.color);
    }
    if (g.flash > 0) {
      canvas.drawRect(Offset.zero & size,
          Paint()..color = Colors.white.withAlpha((g.flash * 46).round()));
    }
  }

  @override
  bool shouldRepaint(covariant _Painter oldDelegate) => true;
}

import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ads.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch any unexpected Flutter/platform errors gracefully to prevent app crash
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter Error: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Platform Error caught: $error');
    return true; // Prevents app crash
  };

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light, // White status bar icons (network, battery, clock)
    statusBarBrightness: Brightness.dark,      // For iOS status bar
    systemNavigationBarColor: Color(0xFF1B1F3B),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  AdService.init(); // await nahi: game turant khule, ads background me load hon
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

class StackGame extends StatefulWidget {
  const StackGame({super.key});

  @override
  State<StackGame> createState() => _StackGameState();
}

class _StackGameState extends State<StackGame>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double bh = 36; // block height
  static const double bottomPad = 50;

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  final List<Block> blocks = [];
  final List<Piece> pieces = [];
  Size _size = Size.zero;

  double baseW = 0, curX = 0, curW = 0, dir = 1, cam = 0, flash = 0;
  int score = 0, best = 0, combo = 0, gameOvers = 0;
  bool over = false;
  bool soundOn = true;
  bool _isRestarting = false;
  bool _isExitDialogShowing = false;
  DateTime _overAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        best = p.getInt('best') ?? 0;
        soundOn = p.getBool('sound') ?? true;
      });
    }).catchError((e) {
      debugPrint('SharedPreferences init error: $e');
    });
    _ticker = createTicker(_tick)..start();
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
      if (!_ticker.isActive && !over) {
        _last = Duration.zero;
        _ticker.start();
      }
    }
  }

  static Color colorFor(int level) =>
      HSVColor.fromAHSV(1, (level * 10 % 360).toDouble(), 0.55, 0.95)
          .toColor();

  void _reset() {
    blocks.clear();
    pieces.clear();
    baseW = _size.width * 0.55;
    blocks.add(Block((_size.width - baseW) / 2, baseW));
    curW = baseW;
    curX = 0;
    dir = 1;
    score = 0;
    combo = 0;
    cam = 0;
    over = false;
  }

  void _tick(Duration elapsed) {
    final double dt =
        ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
    _last = elapsed;
    if (_size == Size.zero) return;

    if (!over) {
      final double speed = min(220.0 + score * 9.0, 620.0);
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
    if (over) {
      if (DateTime.now().difference(_overAt).inMilliseconds > 600) {
        _restart();
      }
      return;
    }
    if (blocks.isEmpty) return;
    final top = blocks.last;
    final level = blocks.length;
    final double left = max(curX, top.x);
    final double right = min(curX + curW, top.x + top.w);
    final double overlap = right - left;

    // Poora miss
    if (overlap <= 0) {
      pieces.add(Piece(curX, level * bh, curW, colorFor(level)));
      _gameOver();
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
    score++;
    curW = nw;
    dir = score.isEven ? 1 : -1;
    curX = dir == 1 ? 0 : _size.width - curW;
  }

  Future<void> _gameOver() async {
    over = true;
    _overAt = DateTime.now();
    gameOvers++;
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
    if (score > best) {
      best = score;
      try {
        final p = await SharedPreferences.getInstance();
        await p.setInt('best', best);
      } catch (e) {
        debugPrint('Could not save best score: $e');
      }
    }
  }

  void _manualRestart() {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
    _reset();
  }

  void _restart() {
    if (_isRestarting) return;
    _isRestarting = true;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    if (gameOvers > 0 && gameOvers % 3 == 0) {
      AdService.showInterstitial(onComplete: () {
        if (mounted) {
          _reset();
          _isRestarting = false;
        }
      });
    } else {
      _reset();
      _isRestarting = false;
    }
  }

  Future<void> _toggleSound() async {
    if (!mounted) return;
    setState(() => soundOn = !soundOn);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('sound', soundOn);
    } catch (e) {
      debugPrint('Could not save sound setting: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, // Forces white status bar icons (network, clock, battery)
        statusBarBrightness: Brightness.dark,      // For iOS
        systemNavigationBarColor: Color(0xFF1B1F3B),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
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
                content: const Text(
                    'Are you sure you want to exit Stack Tower?',
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
          } catch (e) {
            debugPrint('Exit dialog error: $e');
          } finally {
            _isExitDialogShowing = false;
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF1B1F3B),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(builder: (context, c) {
                    final s = Size(c.maxWidth, c.maxHeight);
                    if (_size != s) {
                      final shouldReset =
                          (_size == Size.zero || blocks.isEmpty);
                      _size = s;
                      if (shouldReset && s.width > 0 && s.height > 0) {
                        _reset();
                      }
                    }
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (_) => _onTap(),
                            child: CustomPaint(painter: _Painter(this)),
                          ),
                        ),
                        IgnorePointer(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('$score',
                                      style: const TextStyle(
                                          fontSize: 64,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white)),
                                  Text('BEST $best',
                                      style: const TextStyle(
                                          fontSize: 16, color: Colors.white70)),
                                  if (combo >= 2)
                                    Text('PERFECT x$combo',
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amberAccent)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Top Header Controls (Restart Button & Sound Toggle)
                        Positioned(
                          top: 12,
                          left: 14,
                          right: 14,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Restart Button (Left)
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(28),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.refresh_rounded,
                                      color: Colors.white, size: 24),
                                  tooltip: 'Restart Game',
                                  onPressed: _manualRestart,
                                ),
                              ),
                              // Sound Toggle (Right)
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(28),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    soundOn
                                        ? Icons.volume_up_rounded
                                        : Icons.volume_off_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  tooltip: soundOn ? 'Mute' : 'Unmute',
                                  onPressed: _toggleSound,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (score == 0 && !over)
                          const IgnorePointer(
                            child: Align(
                              alignment: Alignment(0, 0.55),
                              child: Text('TAP to drop the block',
                                  style: TextStyle(
                                      fontSize: 20, color: Colors.white70)),
                            ),
                          ),
                        if (over)
                          Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 28),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: 26),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F1225).withAlpha(240),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                    color: Colors.white24, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(160),
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
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 2.0,
                                          color: Colors.white)),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(20),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Column(
                                          children: [
                                            const Text('SCORE',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white60,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            const SizedBox(height: 4),
                                            Text('$score',
                                                style: const TextStyle(
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white)),
                                          ],
                                        ),
                                        const SizedBox(width: 28),
                                        Container(
                                            width: 1,
                                            height: 36,
                                            color: Colors.white24),
                                        const SizedBox(width: 28),
                                        Column(
                                          children: [
                                            const Text('BEST',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.amberAccent,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            const SizedBox(height: 4),
                                            Text('$best',
                                                style: const TextStyle(
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        Colors.amberAccent)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  // Prominent Play Again / Restart Button
                                  ElevatedButton.icon(
                                    onPressed: _restart,
                                    icon: const Icon(Icons.replay_rounded,
                                        color: Color(0xFF0F1225), size: 24),
                                    label: const Text(
                                      'PLAY AGAIN',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                          color: Color(0xFF0F1225)),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.amberAccent,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 32, vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(30),
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
                const BannerBox(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  final _StackGameState g;
  _Painter(this.g);

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

    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2B2F6B), Color(0xFF0F1230)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    for (int i = 0; i < g.blocks.length; i++) {
      final b = g.blocks[i];
      _rect(canvas, size, b.x, i * _StackGameState.bh, b.w,
          _StackGameState.colorFor(i));
    }
    if (!g.over) {
      final int lvl = g.blocks.length;
      _rect(canvas, size, g.curX, lvl * _StackGameState.bh, g.curW,
          _StackGameState.colorFor(lvl));
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

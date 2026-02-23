import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const SplashScreen({super.key, required this.onFinished});

  @override
  State<SplashScreen> createState() => SplashScreenState();
}

class SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  final math.Random _rng = math.Random();
  final List<_Bubble> _bubbles = [];
  Size _screenSize = Size.zero;
  double _lastTick = 0; // seconds since epoch

  // Drives repaints — no setState needed
  late final AnimationController _tickController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  late final AnimationController _fadeOutController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  bool _disposed = false;
  bool _fadingOut = false;

  @override
  void initState() {
    super.initState();
    _lastTick = DateTime.now().millisecondsSinceEpoch / 1000.0;
    _tickController.addListener(_updateBubbles);
    _startAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenSize = MediaQuery.of(context).size;
  }

  Future<void> _startAnimation() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (_disposed) return;

    for (int i = 0; i < 6; i++) {
      Future.delayed(Duration(milliseconds: i * 120), () {
        if (!_disposed) _spawnBubble();
      });
    }

    _continuousSpawn();

    await Future.delayed(const Duration(milliseconds: 4000));
    if (_disposed) return;
    widget.onFinished();
  }

  void _continuousSpawn() async {
    while (!_disposed && !_fadingOut) {
      await Future.delayed(Duration(milliseconds: 400 + _rng.nextInt(300)));
      if (!_disposed && !_fadingOut) _spawnBubble();
    }
  }

  Future<void> fadeOut() {
    if (_fadingOut) return Future.value();
    _fadingOut = true;
    return _fadeOutController.forward().orCancel.catchError((_) {});
  }

  void _spawnBubble() {
    final s = _screenSize;
    if (s == Size.zero) return;
    final bubbleRadius = 10.0 + _rng.nextDouble() * 24;
    _bubbles.add(_Bubble(
      startX: _rng.nextDouble() * s.width,
      y: s.height + bubbleRadius,
      radius: bubbleRadius,
      speed: 80.0 + _rng.nextDouble() * 100.0, // pixels per second
      wobbleSpeed: 0.5 + _rng.nextDouble() * 1.0,
      opacity: 0.15 + _rng.nextDouble() * 0.35,
      color: _rng.nextBool()
          ? AppColors.primary
          : Color.lerp(AppColors.primary, AppColors.accent, _rng.nextDouble())!,
      phase: _rng.nextDouble() * math.pi * 2,
      popAt: 0.15 + _rng.nextDouble() * 0.5,
      birthTime: DateTime.now().millisecondsSinceEpoch / 1000.0,
    ));
  }

  // Time-based updates: if frames are dropped, bubbles jump to correct position
  void _updateBubbles() {
    final s = _screenSize;
    if (s == Size.zero) return;
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final dt = (now - _lastTick).clamp(0.0, 0.1); // cap at 100ms to avoid huge jumps
    _lastTick = now;

    for (int i = _bubbles.length - 1; i >= 0; i--) {
      final b = _bubbles[i];
      if (b.popped) {
        b.popProgress += dt * 5.0; // ~0.08 per frame at 60fps
        if (b.popProgress >= 1.0) {
          _bubbles.removeAt(i);
        }
      } else {
        final age = now - b.birthTime;
        b.y -= b.speed * dt;
        b.x = b.startX + math.sin(age * b.wobbleSpeed + b.phase) * 20.0;
        if (b.y < s.height * b.popAt) {
          b.popped = true;
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _tickController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fadeOutController,
      builder: (context, child) => Opacity(
        opacity: 1.0 - _fadeOutController.value,
        child: child,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: RepaintBoundary(
          child: CustomPaint(
            painter: _BubblePainter(_bubbles, _tickController),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _Bubble {
  double startX; // original X for wobble calculation
  double x, y, radius, speed, wobbleSpeed, opacity;
  double popAt, popProgress, phase;
  double birthTime;
  Color color;
  bool popped;

  _Bubble({
    required this.startX,
    required this.y,
    required this.radius,
    required this.speed,
    required this.wobbleSpeed,
    required this.opacity,
    required this.color,
    required this.phase,
    required this.popAt,
    required this.birthTime,
  })  : x = startX,
        popped = false,
        popProgress = 0.0;
}

class _BubblePainter extends CustomPainter {
  final List<_Bubble> bubbles;
  _BubblePainter(this.bubbles, Animation<double> repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bubbles) {
      if (b.popped) {
        final t = b.popProgress;
        final expandRadius = b.radius * (1.0 + t * 1.2);
        final ringPaint = Paint()
          ..color = b.color.withOpacity(b.opacity * (1.0 - t) * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * (1.0 - t);
        canvas.drawCircle(Offset(b.x, b.y), expandRadius, ringPaint);
      } else {
        final paint = Paint()
          ..color = b.color.withOpacity(b.opacity * 0.3)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(b.x, b.y), b.radius, paint);

        final ringPaint = Paint()
          ..color = b.color.withOpacity(b.opacity * 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(Offset(b.x, b.y), b.radius, ringPaint);

        final hlPaint = Paint()
          ..color = Colors.white.withOpacity(b.opacity * 0.3)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
          Offset(b.x - b.radius * 0.3, b.y - b.radius * 0.3),
          b.radius * 0.18,
          hlPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

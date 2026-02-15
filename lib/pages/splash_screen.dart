import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const SplashScreen({super.key, required this.onFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  final math.Random _rng = math.Random();
  final List<_Bubble> _bubbles = [];

  late final AnimationController _bubbleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 16), // tick driver
  );

  late final AnimationController _fadeOutController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  Future<void> _startAnimation() async {
    // Spawn bubbles over time
    _bubbleController.addListener(_tickBubbles);
    _bubbleController.repeat();

    // Spawn initial wave of bubbles
    for (int i = 0; i < 12; i++) {
      Future.delayed(Duration(milliseconds: i * 80), () {
        if (!_disposed) _spawnBubble();
      });
    }

    // Keep spawning bubbles
    for (int i = 0; i < 8; i++) {
      Future.delayed(Duration(milliseconds: 1000 + i * 150), () {
        if (!_disposed) _spawnBubble();
      });
    }

    // Fade out and finish
    await Future.delayed(const Duration(milliseconds: 2800));
    if (_disposed) return;
    _fadeOutController.forward().then((_) {
      if (!_disposed) widget.onFinished();
    });
  }

  void _spawnBubble() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    final bubbleRadius = 8.0 + _rng.nextDouble() * 28;
    _bubbles.add(_Bubble(
      x: _rng.nextDouble() * size.width,
      y: size.height + bubbleRadius,
      radius: bubbleRadius,
      speed: 3.0 + _rng.nextDouble() * 4.0,
      wobbleSpeed: 0.5 + _rng.nextDouble() * 1.5,
      wobbleAmount: 10.0 + _rng.nextDouble() * 20,
      opacity: 0.15 + _rng.nextDouble() * 0.4,
      color: _rng.nextBool()
          ? AppColors.primary
          : Color.lerp(AppColors.primary, AppColors.accent, _rng.nextDouble())!,
      phase: _rng.nextDouble() * math.pi * 2,
      popAt: 0.15 + _rng.nextDouble() * 0.5, // pop when reaching this fraction of screen height
      popped: false,
      popProgress: 0.0,
      birthTime: DateTime.now(),
    ));
  }

  void _tickBubbles() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    final now = DateTime.now();
    setState(() {
      for (int i = _bubbles.length - 1; i >= 0; i--) {
        final b = _bubbles[i];
        final age = now.difference(b.birthTime).inMilliseconds / 1000.0;

        if (b.popped) {
          b.popProgress += 0.06;
          if (b.popProgress >= 1.0) {
            _bubbles.removeAt(i);
            continue;
          }
        } else {
          b.y -= b.speed;
          b.x += math.sin(age * b.wobbleSpeed + b.phase) * 0.8;

          // Pop when reaching target height
          if (b.y < size.height * b.popAt) {
            b.popped = true;
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _bubbleController.dispose();
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
        body: Stack(
          children: [
            // Bubbles layer
            CustomPaint(
              painter: _BubblePainter(_bubbles),
              size: Size.infinite,
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble {
  double x, y, radius, speed, wobbleSpeed, wobbleAmount, opacity;
  double popAt, popProgress, phase;
  Color color;
  bool popped;
  DateTime birthTime;

  _Bubble({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.wobbleSpeed,
    required this.wobbleAmount,
    required this.opacity,
    required this.color,
    required this.phase,
    required this.popAt,
    required this.popped,
    required this.popProgress,
    required this.birthTime,
  });
}

class _BubblePainter extends CustomPainter {
  final List<_Bubble> bubbles;
  _BubblePainter(this.bubbles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bubbles) {
      if (b.popped) {
        _drawPop(canvas, b);
      } else {
        _drawBubble(canvas, b);
      }
    }
  }

  void _drawBubble(Canvas canvas, _Bubble b) {
    // Filled circle with glow
    final paint = Paint()
      ..color = b.color.withOpacity(b.opacity * 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(b.x, b.y), b.radius, paint);

    // Ring
    final ringPaint = Paint()
      ..color = b.color.withOpacity(b.opacity * 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(b.x, b.y), b.radius, ringPaint);

    // Highlight
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(b.opacity * 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(b.x - b.radius * 0.3, b.y - b.radius * 0.3),
      b.radius * 0.2,
      highlightPaint,
    );
  }

  void _drawPop(Canvas canvas, _Bubble b) {
    final t = b.popProgress;
    final expandRadius = b.radius * (1.0 + t * 1.5);
    final opacity = b.opacity * (1.0 - t);

    // Expanding ring
    final ringPaint = Paint()
      ..color = b.color.withOpacity(opacity * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * (1.0 - t);
    canvas.drawCircle(Offset(b.x, b.y), expandRadius, ringPaint);

    // Small particles flying out
    final particlePaint = Paint()
      ..color = b.color.withOpacity(opacity * 0.8)
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 6; i++) {
      final angle = (i / 6) * math.pi * 2;
      final dist = b.radius * (0.5 + t * 2.0);
      final px = b.x + math.cos(angle) * dist;
      final py = b.y + math.sin(angle) * dist;
      final particleSize = (b.radius * 0.15) * (1.0 - t);
      canvas.drawCircle(Offset(px, py), particleSize, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

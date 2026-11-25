import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _pageIndex = 0;

  final List<Map<String, dynamic>> _slides = [
    {
      'title': 'Send Packages\nEasily',
      'subtitle': 'Book doorstep pickups in seconds with instant transparent pricing.',
      'icon': Icons.inventory_2_rounded,
      'topText': false,
    },
    {
      'title': 'Track Your\nPackages Live',
      'subtitle': 'Follow your courier meter-by-meter on a live interactive route map.',
      'icon': Icons.route_rounded,
      'topText': true,
    },
    {
      'title': 'Fast & Secure\nDelivery',
      'subtitle': 'OTP-verified handoffs and photo proof for complete peace of mind.',
      'icon': Icons.verified_user_rounded,
      'topText': false,
    },
  ];

  void _onNext() {
    if (_pageIndex < 2) {
      _controller.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Skip', style: TextStyle(color: AppColors.secondaryText, fontWeight: FontWeight.w500)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _pageIndex = i),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  final bool isTopText = slide['topText'] as bool;

                  final textBlock = Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        Text(slide['title'], textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineLarge),
                        const SizedBox(height: 12),
                        Text(slide['subtitle'],
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13, height: 1.5)),
                      ],
                    ),
                  );

                  final illustrationBlock = SizedBox(
                    height: 290,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _OrangeRibbonWavePainter(variant: index),
                      child: Center(
                        child: Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryOrange.withValues(alpha: 0.24),
                                blurRadius: 28,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: Icon(slide['icon'], size: 64, color: AppColors.primaryOrange),
                        ),
                      ),
                    ),
                  );

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: isTopText ? [textBlock, illustrationBlock] : [illustrationBlock, textBlock],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: GestureDetector(
                onTap: _onNext,
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: CustomPaint(
                    painter: _SegmentedSquircleRingPainter(
                      ringColor: _pageIndex == 2 ? AppColors.primaryOrange : AppColors.success,
                    ),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: _pageIndex == 2 ? AppColors.primaryOrange : AppColors.primaryText,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.chevron_right_rounded, color: AppColors.white, size: 30),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrangeRibbonWavePainter extends CustomPainter {
  final int variant;
  _OrangeRibbonWavePainter({required this.variant});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.primaryOrange..style = PaintingStyle.fill;
    final path = Path();
    if (variant == 0) {
      path.moveTo(0, size.height * 0.65);
      path.quadraticBezierTo(size.width * 0.45, size.height * 0.28, size.width, size.height * 0.48);
      path.lineTo(size.width, size.height * 0.85);
      path.quadraticBezierTo(size.width * 0.45, size.height * 0.62, 0, size.height * 0.92);
    } else if (variant == 1) {
      path.moveTo(0, size.height * 0.35);
      path.quadraticBezierTo(size.width * 0.5, size.height * 0.52, size.width, size.height * 0.35);
      path.lineTo(size.width, size.height * 0.72);
      path.quadraticBezierTo(size.width * 0.5, size.height * 0.88, 0, size.height * 0.72);
    } else {
      path.moveTo(0, size.height * 0.48);
      path.quadraticBezierTo(size.width * 0.55, size.height * 0.25, size.width, size.height * 0.65);
      path.lineTo(size.width, size.height * 0.92);
      path.quadraticBezierTo(size.width * 0.55, size.height * 0.60, 0, size.height * 0.85);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OrangeRibbonWavePainter oldDelegate) => oldDelegate.variant != variant;
}

class _SegmentedSquircleRingPainter extends CustomPainter {
  final Color ringColor;
  _SegmentedSquircleRingPainter({required this.ringColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ringColor..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    for (int i = 0; i < 4; i++) {
      canvas.drawArc(rect, (i * math.pi / 2) + 0.18, (math.pi / 2) - 0.36, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedSquircleRingPainter oldDelegate) => oldDelegate.ringColor != ringColor;
}

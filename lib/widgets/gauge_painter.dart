import 'dart:math';
import 'package:flutter/material.dart';

class GaugePainter extends CustomPainter {
  final double value, maxValue, alertThreshold;
  final Color bgColor, needleColor;
  GaugePainter({required this.value, required this.maxValue, required this.alertThreshold, required this.bgColor, required this.needleColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 10;
    const startAngle = pi;
    const sweepAngle = pi;

    final bgPaint = Paint()..color = bgColor..style = PaintingStyle.stroke..strokeWidth = 15..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, bgPaint);

    final percent = (value / maxValue).clamp(0.0, 1.0);
    final valuePaint = Paint()..color = value > alertThreshold ? Colors.red : const Color(0xFFE67E22)..style = PaintingStyle.stroke..strokeWidth = 15..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle * percent, false, valuePaint);

    final needleAngle = pi + (pi * percent);
    final needleEnd = Offset(center.dx + (radius - 20) * cos(needleAngle), center.dy + (radius - 20) * sin(needleAngle));
    final needlePaint = Paint()..color = needleColor..style = PaintingStyle.stroke..strokeWidth = 3;
    canvas.drawLine(center, needleEnd, needlePaint);
    canvas.drawCircle(center, 6, Paint()..color = needleColor);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
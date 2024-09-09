import 'dart:math';

import 'package:flutter/material.dart';

class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({super.key});

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  var visualizer = 1;

  @override
  void initState() {
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true); // Repeats animation back and forth

    _animation = Tween<double>(begin: 0.0, end: -10.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          size: Size(300, 300),
          painter: CurvePainter(_animation.value),
        );
      },
    );

    // return CustomPaint(
    //   size: const Size(300, 300),
    //   painter: CurvePainter(),
    // );
  }
}

class CurvePainter extends CustomPainter {
  final double offsetY;

  CurvePainter(this.offsetY);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    Paint dotPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    // Define the center of the circle and the radius
    Offset center = Offset(size.width / 2, size.height / 2);
    double radius = size.width * 0.35;

    // Define the points in a circular pattern
    List<Offset> points = [];
    int numPoints = 5;
    for (int i = 0; i < numPoints; i++) {
      double angle = (2 * pi / numPoints) * i;
      points.add(Offset(
        center.dx + radius * cos(angle),
        center.dy +
            radius * sin(angle) +
            offsetY, // Add the offsetY to move the dots up and down
      ));
    }

    // Draw the dots
    for (var point in points) {
      canvas.drawCircle(point, 5.0, dotPaint);
    }

    // Draw the smooth curve
    Path path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 1; i < points.length - 1; i++) {
      var nextPoint = points[i + 1];
      var controlPoint = points[i];
      path.quadraticBezierTo(
        controlPoint.dx,
        controlPoint.dy,
        nextPoint.dx,
        nextPoint.dy,
      );
    }

    // Connect the last point back to the first to close the curve
    path.quadraticBezierTo(
      points[points.length - 1].dx,
      points[0].dy,
      points[0].dx,
      points[0].dy,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

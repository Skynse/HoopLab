import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';
import 'package:hooplab/utils/trajectory_prediction.dart';

class TrajectoryOverlay extends StatelessWidget {
  final List<FrameData> frames;
  final Duration currentVideoPosition;
  final Size videoSize;

  const TrajectoryOverlay({
    super.key,
    required this.frames,
    required this.currentVideoPosition,
    required this.videoSize,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: TrajectoryPainter(
        frames: frames,
        currentVideoPosition: currentVideoPosition,
        videoSize: videoSize,
      ),
      size: Size.infinite,
    );
  }
}

class TrajectoryPainter extends CustomPainter {
  final List<FrameData> frames;
  final Duration currentVideoPosition;
  final Size videoSize;

  TrajectoryPainter({
    required this.frames,
    required this.currentVideoPosition,
    required this.videoSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty) return;

    // Calculate scaling from video to widget
    final scaleX = size.width / videoSize.width;
    final scaleY = size.height / videoSize.height;
    final scale = scaleX < scaleY ? scaleX : scaleY; // Maintain aspect ratio

    final offsetX = (size.width - (videoSize.width * scale)) / 2;
    final offsetY = (size.height - (videoSize.height * scale)) / 2;

    // Extract ball trajectory points up to current video time
    final currentTimeMs = currentVideoPosition.inMilliseconds.toDouble();
    final trajectoryPoints = <TrajectoryPoint>[];

    for (final frame in frames) {
      // Only include frames up to current video position
      if (frame.timestamp * 1000 > currentTimeMs) break;

      final ballDetections = frame.detections
          .where((d) => d.label.toLowerCase().contains('ball'))
          .toList();

      if (ballDetections.isNotEmpty) {
        final ball = ballDetections.first;
        // Convert normalized coordinates (0-1) to video pixel coordinates
        final videoX = ball.bbox.centerX * videoSize.width;
        final videoY = ball.bbox.centerY * videoSize.height;

        trajectoryPoints.add(TrajectoryPoint(
          position: Offset(videoX, videoY),
          timestamp: frame.timestamp,
          confidence: ball.confidence,
        ));
      }
    }

    if (trajectoryPoints.isEmpty) return;

    // Clean and filter trajectory points
    final cleanedPoints = _cleanTrajectoryData(trajectoryPoints);

    if (cleanedPoints.length < 2) return;

    // Scale points to widget coordinates
    final scaledPoints = cleanedPoints.map((tp) => Offset(
      tp.position.dx * scale + offsetX,
      tp.position.dy * scale + offsetY,
    )).toList();

    // Draw trajectory path
    _drawTrajectoryPath(canvas, scaledPoints);

    // Draw current ball position
    if (scaledPoints.isNotEmpty) {
      _drawCurrentBall(canvas, scaledPoints.last);
    }

    // Find and draw hoop if detected
    final hoopPosition = _findHoopPosition();
    if (hoopPosition != null && cleanedPoints.length >= 3) {
      final scaledHoop = Offset(
        hoopPosition.dx * scale + offsetX,
        hoopPosition.dy * scale + offsetY,
      );
      _drawHoop(canvas, scaledHoop);

      // Draw prediction
      _drawPrediction(canvas, cleanedPoints, hoopPosition, scale, offsetX, offsetY);
    }
  }

  /// Clean trajectory data by removing outliers and smoothing
  List<TrajectoryPoint> _cleanTrajectoryData(List<TrajectoryPoint> rawPoints) {
    if (rawPoints.length < 3) return rawPoints;

    // Filter by confidence
    final highConfidencePoints = rawPoints
        .where((point) => point.confidence >= 0.5)
        .toList();

    if (highConfidencePoints.length < 3) return rawPoints;

    // Remove outliers based on speed
    final cleaned = <TrajectoryPoint>[highConfidencePoints.first];

    for (int i = 1; i < highConfidencePoints.length; i++) {
      final current = highConfidencePoints[i];
      final previous = cleaned.last;

      final distance = (current.position - previous.position).distance;
      final timeDiff = current.timestamp - previous.timestamp;
      final speed = timeDiff > 0 ? distance / timeDiff : 0;

      // Filter unrealistic movements
      if (speed < 2000.0 && distance < 200.0) {
        cleaned.add(current);
      }
    }

    return cleaned;
  }

  /// Draw the trajectory path
  void _drawTrajectoryPath(Canvas canvas, List<Offset> points) {
    if (points.length < 2) return;

    final pathPaint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);

    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    canvas.drawPath(path, pathPaint);
  }

  /// Draw current ball position
  void _drawCurrentBall(Canvas canvas, Offset position) {
    // Ball shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(position.dx + 2, position.dy + 2),
      8,
      shadowPaint,
    );

    // Ball
    final ballPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, 6, ballPaint);

    // Ball highlight
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(position.dx - 2, position.dy - 2),
      2,
      highlightPaint,
    );
  }

  /// Find hoop position from detections
  Offset? _findHoopPosition() {
    for (final frame in frames) {
      final hoopDetections = frame.detections
          .where((d) =>
              d.label.toLowerCase().contains('hoop') ||
              d.label.toLowerCase().contains('rim') ||
              d.label.toLowerCase().contains('basket'))
          .toList();

      if (hoopDetections.isNotEmpty) {
        final hoop = hoopDetections.first;
        // Convert normalized coordinates (0-1) to video pixel coordinates
        final videoX = hoop.bbox.centerX * videoSize.width;
        final videoY = hoop.bbox.centerY * videoSize.height;
        return Offset(videoX, videoY);
      }
    }
    return null;
  }

  /// Draw hoop
  void _drawHoop(Canvas canvas, Offset position) {
    // Hoop rim
    final hoopPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(position, 25, hoopPaint);

    // Hoop center dot
    final centerPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, 3, centerPaint);
  }

  /// Draw prediction trajectory
  void _drawPrediction(Canvas canvas, List<TrajectoryPoint> points,
                      Offset hoopPosition, double scale, double offsetX, double offsetY) {
    final ballPoints = points.map((tp) => tp.position).toList();

    final predictedPoints = TrajectoryPredictor.predictTrajectory(
      ballPoints: ballPoints,
      hoopPosition: hoopPosition,
      predictionSteps: 10,
    );

    if (predictedPoints.isEmpty) return;

    // Scale predicted points
    final scaledPredicted = predictedPoints.map((pos) => Offset(
      pos.dx * scale + offsetX,
      pos.dy * scale + offsetY,
    )).toList();

    // Check if shot will go in
    final willScore = TrajectoryPredictor.willShotGoIn(
      ballPoints: ballPoints,
      hoopPosition: hoopPosition,
    );

    // Draw dashed prediction line
    final predictedPaint = Paint()
      ..color = willScore
          ? Colors.green.withValues(alpha: 0.8)
          : Colors.red.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    _drawDashedPath(canvas, scaledPredicted, predictedPaint);
  }

  /// Draw dashed line
  void _drawDashedPath(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;

    for (int i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];

      final distance = (end - start).distance;
      const dashLength = 8.0;
      const gapLength = 4.0;

      if (distance > 0) {
        final direction = (end - start) / distance;
        double currentDistance = 0;
        bool drawDash = true;

        while (currentDistance < distance) {
          final segmentLength = drawDash ? dashLength : gapLength;
          final segmentEnd = (currentDistance + segmentLength).clamp(0.0, distance);

          if (drawDash) {
            final segmentStart = start + direction * currentDistance;
            final segmentEndPoint = start + direction * segmentEnd;
            canvas.drawLine(segmentStart, segmentEndPoint, paint);
          }

          currentDistance += segmentLength;
          drawDash = !drawDash;
        }
      }
    }
  }

  @override
  bool shouldRepaint(TrajectoryPainter oldDelegate) {
    return currentVideoPosition != oldDelegate.currentVideoPosition ||
           frames != oldDelegate.frames;
  }
}

class TrajectoryPoint {
  final Offset position;
  final double timestamp;
  final double confidence;

  TrajectoryPoint({
    required this.position,
    required this.timestamp,
    required this.confidence,
  });
}
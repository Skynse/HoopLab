import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';
import 'package:hooplab/utils/trajectory_prediction.dart';

class BallTrajectoryPoint {
  final Offset position;
  final double timestamp;
  final double confidence;

  BallTrajectoryPoint({
    required this.position,
    required this.timestamp,
    required this.confidence,
  });
}

class SimpleBallTrajectory extends CustomPainter {
  final List<FrameData> frames;
  final int currentFrame;
  final Size videoSize;
  final Size widgetSize;
  final double aspectRatio;

  SimpleBallTrajectory({
    required this.frames,
    required this.currentFrame,
    required this.videoSize,
    required this.widgetSize,
    required this.aspectRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty) return;

    // Extract ball trajectory with confidence scores
    List<BallTrajectoryPoint> trajectoryPoints = [];

    for (final frame in frames) {
      final ballDetections = frame.detections
          .where((d) => d.label.toLowerCase().contains('ball'))
          .toList();

      if (ballDetections.isNotEmpty) {
        final ball = ballDetections.first;
        trajectoryPoints.add(
          BallTrajectoryPoint(
            position: Offset(ball.bbox.centerX, ball.bbox.centerY),
            timestamp: frame.timestamp,
            confidence: ball.confidence,
          ),
        );
      }
    }

    if (trajectoryPoints.isEmpty) return;

    // Clean trajectory data using their methods
    final cleanedTrajectory = _cleanTrajectoryData(trajectoryPoints);
    final ballPositions = cleanedTrajectory.map((tp) => tp.position).toList();

    if (ballPositions.isEmpty) return;

    // Scale coordinates to fit the widget
    final scaleX = size.width / videoSize.width;
    final scaleY = size.height / videoSize.height;
    final scale = scaleX < scaleY
        ? scaleX
        : scaleY; // Use smaller scale to maintain aspect ratio

    final offsetX = (size.width - (videoSize.width * scale)) / 2;
    final offsetY = (size.height - (videoSize.height * scale)) / 2;

    List<Offset> scaledPositions = ballPositions
        .map(
          (pos) => Offset(pos.dx * scale + offsetX, pos.dy * scale + offsetY),
        )
        .toList();

    // Draw the trajectory path up to current frame
    final currentPositions = scaledPositions.take(currentFrame + 1).toList();

    if (currentPositions.length > 1) {
      // Draw the actual path
      final pathPaint = Paint()
        ..color = const Color(0xFF1565C0)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      path.moveTo(currentPositions.first.dx, currentPositions.first.dy);

      for (int i = 1; i < currentPositions.length; i++) {
        path.lineTo(currentPositions[i].dx, currentPositions[i].dy);
      }

      canvas.drawPath(path, pathPaint);

      // Find hoop position for shot analysis
      final hoopPosition = _findHoopPosition();

      // Draw predicted trajectory (using their linear regression method)
      if (currentPositions.length >= 3) {
        final originalPositions = currentPositions
            .map(
              (pos) => Offset(
                (pos.dx - offsetX) / scale,
                (pos.dy - offsetY) / scale,
              ),
            )
            .toList();

        final predictedPoints = TrajectoryPredictor.predictTrajectory(
          ballPoints: originalPositions,
          hoopPosition: hoopPosition,
          predictionSteps: 15,
        );

        if (predictedPoints.isNotEmpty) {
          // Scale predicted points
          final scaledPredicted = predictedPoints
              .map(
                (pos) =>
                    Offset(pos.dx * scale + offsetX, pos.dy * scale + offsetY),
              )
              .toList();

          // Check shot success prediction
          bool willScore = false;
          if (hoopPosition != null) {
            willScore = TrajectoryPredictor.willShotGoIn(
              ballPoints: originalPositions,
              hoopPosition: hoopPosition,
            );
          }

          // Draw predicted path (color based on shot prediction)
          final predictedPaint = Paint()
            ..color = willScore
                ? Colors.green.withOpacity(0.8)
                : Colors.red.withOpacity(0.7)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;

          _drawDashedPath(canvas, scaledPredicted, predictedPaint);
        }
      }

      // Draw hoop if detected
      if (hoopPosition != null) {
        final scaledHoopPos = Offset(
          hoopPosition.dx * scale + offsetX,
          hoopPosition.dy * scale + offsetY,
        );

        // Hoop rim
        final hoopPaint = Paint()
          ..color = Colors.red
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(scaledHoopPos, 25, hoopPaint);

        // Hoop center
        final centerPaint = Paint()
          ..color = Colors.red.withOpacity(0.3)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(scaledHoopPos, 3, centerPaint);
      }

      // Draw current ball position
      if (currentFrame < currentPositions.length) {
        final currentPos = currentPositions[currentFrame];

        // Ball shadow
        final shadowPaint = Paint()
          ..color = Colors.black.withOpacity(0.3)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
          Offset(currentPos.dx + 2, currentPos.dy + 2),
          8,
          shadowPaint,
        );

        // Ball
        final ballPaint = Paint()
          ..color = const Color(0xFF1565C0)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(currentPos, 6, ballPaint);

        // Ball highlight
        final highlightPaint = Paint()
          ..color = Colors.white.withOpacity(0.7)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
          Offset(currentPos.dx - 2, currentPos.dy - 2),
          2,
          highlightPaint,
        );
      }
    }
  }

  /// Find hoop position from frame detections
  Offset? _findHoopPosition() {
    for (final frame in frames) {
      final hoopDetections = frame.detections
          .where(
            (d) =>
                d.label.toLowerCase().contains('hoop') ||
                d.label.toLowerCase().contains('rim') ||
                d.label.toLowerCase().contains('basket'),
          )
          .toList();

      if (hoopDetections.isNotEmpty) {
        final hoop = hoopDetections.first;
        return Offset(hoop.bbox.centerX, hoop.bbox.centerY);
      }
    }
    return null;
  }

  /// Clean trajectory data using filtering techniques similar to the GitHub repo
  List<BallTrajectoryPoint> _cleanTrajectoryData(
    List<BallTrajectoryPoint> rawPoints,
  ) {
    if (rawPoints.length < 3) return rawPoints;

    List<BallTrajectoryPoint> cleaned = [];

    // Step 1: Filter by confidence threshold (remove low-confidence detections)
    final confidenceThreshold = 0.5;
    final highConfidencePoints = rawPoints
        .where((point) => point.confidence >= confidenceThreshold)
        .toList();

    if (highConfidencePoints.length < 3) {
      return rawPoints; // Fallback to original if too few high-confidence points
    }

    // Step 2: Remove outliers using distance-based filtering
    cleaned.add(highConfidencePoints.first);

    for (int i = 1; i < highConfidencePoints.length; i++) {
      final current = highConfidencePoints[i];
      final previous = cleaned.last;

      // Calculate distance and time difference
      final distance = (current.position - previous.position).distance;
      final timeDiff = current.timestamp - previous.timestamp;

      // Calculate speed (pixels per second)
      final speed = timeDiff > 0 ? distance / timeDiff : 0;

      // Filter out unrealistic movements (too fast = likely detection error)
      const maxReasonableSpeed = 2000.0; // pixels per second
      const maxReasonableDistance = 200.0; // pixels

      if (speed < maxReasonableSpeed && distance < maxReasonableDistance) {
        cleaned.add(current);
      } else {
        debugPrint(
          '🏀 Filtered out outlier: speed=${speed.toStringAsFixed(1)}px/s, distance=${distance.toStringAsFixed(1)}px',
        );
      }
    }

    // Step 3: Smooth trajectory using moving average (similar to their data cleaning)
    if (cleaned.length >= 3) {
      cleaned = _applySmoothingFilter(cleaned);
    }

    debugPrint(
      '🏀 Cleaned trajectory: ${rawPoints.length} → ${cleaned.length} points',
    );
    return cleaned;
  }

  /// Apply smoothing filter to reduce noise in trajectory
  List<BallTrajectoryPoint> _applySmoothingFilter(
    List<BallTrajectoryPoint> points,
  ) {
    if (points.length < 3) return points;

    List<BallTrajectoryPoint> smoothed = [];
    const windowSize = 3;

    // Keep first point
    smoothed.add(points.first);

    // Apply moving average for middle points
    for (int i = 1; i < points.length - 1; i++) {
      double sumX = 0, sumY = 0;
      int count = 0;

      // Average with neighbors
      for (
        int j = max(0, i - windowSize ~/ 2);
        j <= min(points.length - 1, i + windowSize ~/ 2);
        j++
      ) {
        sumX += points[j].position.dx;
        sumY += points[j].position.dy;
        count++;
      }

      final smoothedPosition = Offset(sumX / count, sumY / count);
      smoothed.add(
        BallTrajectoryPoint(
          position: smoothedPosition,
          timestamp: points[i].timestamp,
          confidence: points[i].confidence,
        ),
      );
    }

    // Keep last point
    smoothed.add(points.last);

    return smoothed;
  }

  /// Draw dashed line for prediction (similar to their visualization)
  void _drawDashedPath(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;

    for (int i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];

      // Draw dashed line segments
      final distance = (end - start).distance;
      const dashLength = 8.0;
      const gapLength = 4.0;

      if (distance > 0) {
        final direction = (end - start) / distance;
        double currentDistance = 0;
        bool drawDash = true;

        while (currentDistance < distance) {
          final segmentLength = drawDash ? dashLength : gapLength;
          final segmentEnd = min(currentDistance + segmentLength, distance);

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
  bool shouldRepaint(SimpleBallTrajectory oldDelegate) {
    return currentFrame != oldDelegate.currentFrame ||
        frames != oldDelegate.frames;
  }
}

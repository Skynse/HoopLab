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
        // Bounding box coordinates are already in pixel coordinates (not normalized)
        final videoX = ball.bbox.centerX;
        final videoY = ball.bbox.centerY;

        trajectoryPoints.add(
          TrajectoryPoint(
            position: Offset(videoX, videoY),
            timestamp: frame.timestamp,
            confidence: ball.confidence,
          ),
        );
      }
    }

    if (trajectoryPoints.isEmpty) return;

    // Clean and filter trajectory points
    final cleanedPoints = _cleanTrajectoryData(trajectoryPoints);

    if (cleanedPoints.length < 2) return;

    // Scale points to widget coordinates
    final scaledPoints = cleanedPoints
        .map(
          (tp) => Offset(
            tp.position.dx * scale + offsetX,
            tp.position.dy * scale + offsetY,
          ),
        )
        .toList();

    // Draw trajectory path
    _drawTrajectoryPath(canvas, scaledPoints);

    // Draw current ball position
    if (scaledPoints.isNotEmpty) {
      _drawCurrentBall(canvas, scaledPoints.last, scale, offsetX, offsetY);
    }

    // Find and draw hoop if detected
    final hoopPosition = _findHoopPosition();
    if (hoopPosition != null && cleanedPoints.length >= 3) {
      final scaledHoop = Offset(
        hoopPosition.dx * scale + offsetX,
        hoopPosition.dy * scale + offsetY,
      );
      _drawHoop(canvas, scaledHoop);

      // Hoop position now updates dynamically with camera movement

      // Draw prediction
      _drawPrediction(
        canvas,
        cleanedPoints,
        hoopPosition,
        scale,
        offsetX,
        offsetY,
      );
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

  /// Draw current ball position with debug bounding box
  void _drawCurrentBall(
    Canvas canvas,
    Offset position,
    double scale,
    double offsetX,
    double offsetY,
  ) {
    // Find the ball detection at current time for bounding box
    final currentTimeMs = currentVideoPosition.inMilliseconds.toDouble();
    BoundingBox? ballBBox;

    for (final frame in frames) {
      if (frame.timestamp * 1000 > currentTimeMs) break;

      final ballDetections = frame.detections
          .where((d) => d.label.toLowerCase().contains('ball'))
          .toList();

      if (ballDetections.isNotEmpty) {
        ballBBox = ballDetections.first.bbox;
      }
    }

    // Draw bounding box if available (scaled to widget coordinates)
    if (ballBBox != null) {
      final bboxPaint = Paint()
        ..color = Colors.yellow
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      final rect = Rect.fromLTRB(
        ballBBox.x1 * scale + offsetX,
        ballBBox.y1 * scale + offsetY,
        ballBBox.x2 * scale + offsetX,
        ballBBox.y2 * scale + offsetY,
      );

      canvas.drawRect(rect, bboxPaint);
    }

    // Ball shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(position.dx + 2, position.dy + 2), 8, shadowPaint);

    // Ball
    final ballPaint = Paint()
      ..color = const Color(0xFF1565C0)
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

  /// Find hoop position from detections at current video time
  /// Falls back to nearest hoop detection if not found at exact time
  Offset? _findHoopPosition() {
    final currentTimeMs = currentVideoPosition.inMilliseconds.toDouble();

    // First, try to find hoop in frames near current time
    FrameData? frameWithHoop;
    double minTimeDiff = double.infinity;

    for (final frame in frames) {
      final frameTimeMs = frame.timestamp * 1000;

      // Only consider frames up to current time (already played)
      if (frameTimeMs > currentTimeMs) break;

      final hasHoop = frame.detections.any(
        (d) =>
            d.label.toLowerCase().contains('hoop') ||
            d.label.toLowerCase().contains('rim') ||
            d.label.toLowerCase().contains('basket'),
      );

      if (hasHoop) {
        final timeDiff = (frameTimeMs - currentTimeMs).abs();
        if (timeDiff < minTimeDiff) {
          minTimeDiff = timeDiff;
          frameWithHoop = frame;
        }
      }
    }

    if (frameWithHoop == null) return null;

    final hoopDetections = frameWithHoop.detections
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

    return null;
  }

  /// Get hoop bounding box at current video time
  BoundingBox? _findHoopBBox() {
    final currentTimeMs = currentVideoPosition.inMilliseconds.toDouble();

    FrameData? closestFrame;
    double minTimeDiff = double.infinity;

    for (final frame in frames) {
      final frameTimeMs = frame.timestamp * 1000;
      final timeDiff = (frameTimeMs - currentTimeMs).abs();

      if (timeDiff < minTimeDiff) {
        minTimeDiff = timeDiff;
        closestFrame = frame;
      }

      if (frameTimeMs > currentTimeMs + 100) break;
    }

    if (closestFrame == null) return null;

    final hoopDetections = closestFrame.detections
        .where(
          (d) =>
              d.label.toLowerCase().contains('hoop') ||
              d.label.toLowerCase().contains('rim') ||
              d.label.toLowerCase().contains('basket'),
        )
        .toList();

    if (hoopDetections.isNotEmpty) {
      return hoopDetections.first.bbox;
    }

    return null;
  }

  /// Draw hoop
  void _drawHoop(Canvas canvas, Offset position) {
    // Get actual hoop size if available
    final hoopBBox = _findHoopBBox();
    final hoopRadius = hoopBBox != null ? (hoopBBox.width / 2) : 25.0;

    // Hoop rim
    final hoopPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(position, hoopRadius, hoopPaint);

    // Hoop center dot
    final centerPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, 3, centerPaint);
  }

  /// Draw prediction trajectory
  void _drawPrediction(
    Canvas canvas,
    List<TrajectoryPoint> points,
    Offset hoopPosition,
    double scale,
    double offsetX,
    double offsetY,
  ) {
    final ballPoints = points.map((tp) => tp.position).toList();

    // Check if shot will go in
    final willScore = TrajectoryPredictor.willShotGoIn(
      ballPoints: ballPoints,
      hoopPosition: hoopPosition,
    );

    if (willScore) {
      // Draw normal prediction for makes
      final predictedPoints = TrajectoryPredictor.predictTrajectory(
        ballPoints: ballPoints,
        hoopPosition: hoopPosition,
        predictionSteps: 10,
      );

      if (predictedPoints.isEmpty) return;

      // Scale predicted points
      final scaledPredicted = predictedPoints
          .map(
            (pos) => Offset(pos.dx * scale + offsetX, pos.dy * scale + offsetY),
          )
          .toList();

      // Draw green dashed prediction line for makes
      final predictedPaint = Paint()
        ..color = Colors.green.withValues(alpha: 0.8)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      _drawDashedPath(canvas, scaledPredicted, predictedPaint);
    } else {
      // Draw corrected arc for misses
      final correctedArc = TrajectoryPredictor.predictCorrectedArc(
        ballPoints: ballPoints,
        hoopPosition: hoopPosition,
        predictionSteps: 30,
      );

      if (correctedArc.isEmpty) return;

      // Scale corrected arc points
      final scaledCorrected = correctedArc
          .map(
            (pos) => Offset(pos.dx * scale + offsetX, pos.dy * scale + offsetY),
          )
          .toList();

      // Draw blue dashed line for the corrected arc
      final correctedPaint = Paint()
        ..color = Colors.green.withValues(alpha: 0.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      _drawDashedPath(canvas, scaledCorrected, correctedPaint);

      // Draw feedback text
      _drawShotFeedback(
        canvas,
        ballPoints,
        hoopPosition,
        scale,
        offsetX,
        offsetY,
      );
    }
  }

  /// Draw shot feedback text for missed shots
  void _drawShotFeedback(
    Canvas canvas,
    List<Offset> ballPoints,
    Offset hoopPosition,
    double scale,
    double offsetX,
    double offsetY,
  ) {
    if (ballPoints.length < 3) return;

    // Get the last point of the actual trajectory
    final lastBallPoint = ballPoints.last;

    // Calculate horizontal difference
    final horizontalDiff = lastBallPoint.dx - hoopPosition.dx;
    final verticalDiff = lastBallPoint.dy - hoopPosition.dy;

    // Determine feedback messages
    String horizontalFeedback = '';
    String verticalFeedback = '';

    const horizontalThreshold = 30.0; // pixels
    const verticalThreshold = 50.0; // pixels

    // Horizontal feedback
    if (horizontalDiff.abs() > horizontalThreshold) {
      if (horizontalDiff > 0) {
        horizontalFeedback = 'Aim ${(horizontalDiff / 10).round() * 10}px LEFT';
      } else {
        horizontalFeedback =
            'Aim ${(horizontalDiff.abs() / 10).round() * 10}px RIGHT';
      }
    }

    // Vertical feedback (arc height)
    if (verticalDiff > verticalThreshold) {
      verticalFeedback = 'Higher arc needed';
    } else if (verticalDiff < -verticalThreshold) {
      verticalFeedback = 'Lower arc needed';
    }

    // Combine feedback
    List<String> feedbackLines = [];
    if (horizontalFeedback.isNotEmpty) feedbackLines.add(horizontalFeedback);
    if (verticalFeedback.isNotEmpty) feedbackLines.add(verticalFeedback);

    if (feedbackLines.isEmpty) {
      feedbackLines.add('Close! Small adjustment needed');
    }

    // Position feedback text near the hoop
    final textX = hoopPosition.dx * scale + offsetX;
    final textY = hoopPosition.dy * scale + offsetY - 60;

    // Draw background for text
    for (int i = 0; i < feedbackLines.length; i++) {
      final text = feedbackLines[i];
      final textSpan = TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(color: Colors.black, offset: Offset(1, 1), blurRadius: 3),
          ],
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();

      // Draw semi-transparent background
      final backgroundRect = Rect.fromLTWH(
        textX - textPainter.width / 2 - 8,
        textY + (i * 25) - 4,
        textPainter.width + 16,
        textPainter.height + 8,
      );

      final backgroundPaint = Paint()
        ..color = Colors.blue.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(backgroundRect, const Radius.circular(8)),
        backgroundPaint,
      );

      // Draw text
      textPainter.paint(
        canvas,
        Offset(textX - textPainter.width / 2, textY + (i * 25)),
      );
    }
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
          final segmentEnd = (currentDistance + segmentLength).clamp(
            0.0,
            distance,
          );

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

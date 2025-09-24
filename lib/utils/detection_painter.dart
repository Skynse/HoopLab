import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:hooplab/models/clip.dart';

class TrajectoryPoint {
  final Offset position;
  final double timestamp;
  final Offset velocity;

  TrajectoryPoint(this.position, this.timestamp, this.velocity);
}

class PredictionResult {
  final List<Offset> predictedPath;
  final bool willEnterHoop;
  final double confidence;
  final Offset? hoopEntryPoint;

  PredictionResult(
    this.predictedPath,
    this.willEnterHoop,
    this.confidence,
    this.hoopEntryPoint,
  );
}

class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final Size videoSize;
  final Size widgetSize;
  final double aspectRatio;
  final List<FrameData> allFrames;
  final int currentFrame;
  final bool showTrajectories;
  final bool? showEstimatedPath;

  // Physics constants for ball trajectory
  static const double gravity = 9.81; // m/s^2 (adjust scale as needed)
  static const double pixelsPerMeter =
      100.0; // Adjust based on your court scale

  DetectionPainter({
    required this.detections,
    required this.videoSize,
    required this.widgetSize,
    required this.aspectRatio,
    required this.allFrames,
    required this.currentFrame,
    this.showEstimatedPath,
    this.showTrajectories = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (videoSize.width == 0 || videoSize.height == 0) return;

    // Calculate the actual video display area within the widget
    final widgetAspectRatio = size.width / size.height;

    final videoAspectRatio = aspectRatio;

    double videoDisplayWidth, videoDisplayHeight;
    double offsetX = 0, offsetY = 0;

    if (widgetAspectRatio > videoAspectRatio) {
      // Widget is wider than video - video will have pillarboxing (black bars on sides)
      videoDisplayHeight = size.height;
      videoDisplayWidth = videoDisplayHeight * videoAspectRatio;
      offsetX = (size.width - videoDisplayWidth) / 2;
    } else {
      // Widget is taller than video - video will have letterboxing (black bars on top/bottom)
      videoDisplayWidth = size.width;
      videoDisplayHeight = videoDisplayWidth / videoAspectRatio;
      offsetY = (size.height - videoDisplayHeight) / 2;
    }

    // Calculate scale factors from video coordinates to display coordinates
    final scaleX = videoDisplayWidth / videoSize.width;
    final scaleY = videoDisplayHeight / videoSize.height;

    if (showTrajectories) {
      _drawTrajectories(canvas, scaleX, scaleY, offsetX, offsetY);
    }

    // Draw predicted trajectories and optimal paths
    _drawPredictedTrajectories(canvas, scaleX, scaleY, offsetX, offsetY);

    // Draw current frame detections
    _drawCurrentDetections(canvas, size, scaleX, scaleY, offsetX, offsetY);
  }

  void _drawTrajectories(
    Canvas canvas,
    double scaleX,
    double scaleY,
    double offsetX,
    double offsetY,
  ) {
    // Group detections by track ID
    Map<int, List<Offset>> trajectories = {};

    // Collect all detection positions for each track
    for (final frame in allFrames) {
      if (frame.frameNumber > currentFrame) {
        continue; // Only show past and current
      }

      if (currentFrame > 1) {
        var lastFrameIndex = currentFrame - 1;

        List<Detection> currentBalls = frame.detections
            .where((d) => d.label == "ball")
            .toList();

        // Get previous frame balls
        List<Detection> previousBalls = allFrames
            .where((f) => f.frameNumber == lastFrameIndex)
            .expand((f) => f.detections)
            .where((d) => d.label == "ball")
            .toList();

        for (var c in currentBalls) {
          var previousBall = previousBalls.first;

          double dt = c.timestamp - previousBall.timestamp;
          double vx = (c.bbox.centerX - previousBall.bbox.centerX) / dt;
          double vy = (c.bbox.centerY - previousBall.bbox.centerY) / dt;

          double vel = sqrt(vx * vx + vy * vy);

          print("Current velcoity: $vel");
        }
      }

      for (final detection in frame.detections) {
        final trackId = detection.trackId;
        final centerX = (detection.bbox.centerX * scaleX) + offsetX;
        final centerY = (detection.bbox.centerY * scaleY) + offsetY;

        trajectories.putIfAbsent(trackId, () => []);
        trajectories[trackId]!.add(Offset(centerX, centerY));
      }
    }

    // Draw trajectory lines for each track
    for (final entry in trajectories.entries) {
      final trackId = entry.key;
      final points = entry.value;

      if (points.length < 2) continue; // Need at least 2 points to draw a line

      final color = _getTrackColor(trackId);
      final trajectoryPaint = Paint()
        ..color = color.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      // Draw lines between consecutive points
      for (int i = 0; i < points.length - 1; i++) {
        canvas.drawLine(points[i], points[i + 1], trajectoryPaint);
      }

      // Draw small circles at each trajectory point
      final pointPaint = Paint()
        ..color = color.withOpacity(0.4)
        ..style = PaintingStyle.fill;

      for (final point in points) {
        canvas.drawCircle(point, 2, pointPaint);
      }
    }
  }

  void _drawCurrentDetections(
    Canvas canvas,
    Size size,
    double scaleX,
    double scaleY,
    double offsetX,
    double offsetY,
  ) {
    if (detections.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < detections.length; i++) {
      final detection = detections[i];

      // Get color based on track ID
      final color = _getTrackColor(detection.trackId);
      paint.color = color;

      double x1_norm = detection.bbox.x1 / videoSize.width;
      double y1_norm = detection.bbox.y1 / videoSize.height;
      double x2_norm = detection.bbox.x2 / videoSize.width;
      double y2_norm = detection.bbox.y2 / videoSize.height;

      double real_x1 = x1_norm * widgetSize.width;
      double real_y1 = y1_norm * widgetSize.height;
      double real_x2 = x2_norm * widgetSize.width;
      double real_y2 = y2_norm * widgetSize.height;

      final rect = Rect.fromLTRB(
        real_x1 + offsetX,
        real_y1 + offsetY,
        real_x2 + offsetX,
        real_y2 + offsetY,
      );

      // Draw bounding box
      canvas.drawRect(rect, paint);

      // Draw confidence and track ID
      final text =
          '🏀 ${detection.label} (${(detection.confidence * 100).toStringAsFixed(0)}%)';
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black87,
        ),
      );
      textPainter.layout();

      // Position text above the bounding box
      final textOffset = Offset(
        rect.left,
        (rect.top - textPainter.height - 4).clamp(
          0.0,
          size.height - textPainter.height,
        ),
      );
      textPainter.paint(canvas, textOffset);

      // Draw center point (larger and more prominent than trajectory points)
      final centerPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(rect.center, 5, centerPaint);

      // Draw white outline on center point for better visibility
      final outlinePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(rect.center, 5, outlinePaint);
    }
  }

  void _drawPredictedTrajectories(
    Canvas canvas,
    double scaleX,
    double scaleY,
    double offsetX,
    double offsetY,
  ) {
    // Get current hoop position (adaptive detection)
    final hoopPosition = _detectHoopPosition(scaleX, scaleY, offsetX, offsetY);
    if (hoopPosition == null) return;

    // Draw hoop
    _drawHoop(canvas, hoopPosition);

    // Get ball trajectories for prediction
    final ballTrajectories = _getBallTrajectories(
      scaleX,
      scaleY,
      offsetX,
      offsetY,
    );

    for (final entry in ballTrajectories.entries) {
      final trackId = entry.key;
      final trajectoryPoints = entry.value;

      if (trajectoryPoints.length < 3)
        continue; // Need at least 3 points for prediction

      // Predict trajectory
      final prediction = _predictBallTrajectory(trajectoryPoints, hoopPosition);

      // Draw predicted path
      _drawPredictedPath(canvas, prediction, _getTrackColor(trackId));

      // Draw optimal shot path
      if (trajectoryPoints.isNotEmpty) {
        final optimalPath = _calculateOptimalShotPath(
          trajectoryPoints.last.position,
          hoopPosition,
        );
        _drawOptimalPath(canvas, optimalPath);
      }
    }
  }

  Offset? _detectHoopPosition(
    double scaleX,
    double scaleY,
    double offsetX,
    double offsetY,
  ) {
    // Look for hoop detections in recent frames
    for (
      int i = max(0, currentFrame - 5);
      i <= currentFrame && i < allFrames.length;
      i++
    ) {
      final frame = allFrames[i];
      for (final detection in frame.detections) {
        if (detection.label.toLowerCase().contains('hoop') ||
            detection.label.toLowerCase().contains('basket') ||
            detection.label.toLowerCase().contains('rim')) {
          final centerX = (detection.bbox.centerX * scaleX) + offsetX;
          final centerY = (detection.bbox.centerY * scaleY) + offsetY;
          return Offset(centerX, centerY);
        }
      }
    }

    // If no hoop detected, use estimated position based on court geometry
    // This is a fallback - you might want to implement more sophisticated hoop detection
    return Offset(
      offsetX + (videoDisplayWidth(scaleX) * 0.85),
      offsetY + (videoDisplayHeight(scaleY) * 0.3),
    );
  }

  double videoDisplayWidth(double scaleX) => videoSize.width * scaleX;
  double videoDisplayHeight(double scaleY) => videoSize.height * scaleY;

  void _drawHoop(Canvas canvas, Offset hoopPosition) {
    final hoopPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    // Draw hoop rim
    canvas.drawCircle(hoopPosition, 25, hoopPaint);

    // Draw backboard
    final backboardPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawLine(
      Offset(hoopPosition.dx - 15, hoopPosition.dy - 35),
      Offset(hoopPosition.dx + 15, hoopPosition.dy - 35),
      backboardPaint,
    );
  }

  Map<int, List<TrajectoryPoint>> _getBallTrajectories(
    double scaleX,
    double scaleY,
    double offsetX,
    double offsetY,
  ) {
    Map<int, List<TrajectoryPoint>> trajectories = {};

    // Collect ball positions with velocity calculations
    for (int i = 0; i < min(allFrames.length, currentFrame + 1); i++) {
      final frame = allFrames[i];

      for (final detection in frame.detections) {
        if (detection.label != "ball") continue;

        final trackId = detection.trackId;
        final centerX = (detection.bbox.centerX * scaleX) + offsetX;
        final centerY = (detection.bbox.centerY * scaleY) + offsetY;
        final position = Offset(centerX, centerY);

        trajectories.putIfAbsent(trackId, () => []);
        final points = trajectories[trackId]!;

        Offset velocity = Offset.zero;
        if (points.isNotEmpty) {
          final lastPoint = points.last;
          final dt = detection.timestamp - lastPoint.timestamp;
          if (dt > 0) {
            velocity = Offset(
              (position.dx - lastPoint.position.dx) / dt,
              (position.dy - lastPoint.position.dy) / dt,
            );
          }
        }

        points.add(TrajectoryPoint(position, detection.timestamp, velocity));
      }
    }

    return trajectories;
  }

  PredictionResult _predictBallTrajectory(
    List<TrajectoryPoint> points,
    Offset hoopPosition,
  ) {
    if (points.length < 3) {
      return PredictionResult([], false, 0.0, null);
    }

    // Use last few points to calculate current velocity and acceleration
    final recentPoints = points.length > 5
        ? points.sublist(points.length - 5)
        : points;

    // Calculate average velocity from recent points
    Offset avgVelocity = Offset.zero;
    double totalWeight = 0.0;

    for (int i = 1; i < recentPoints.length; i++) {
      final weight = i.toDouble(); // Give more weight to recent points
      avgVelocity += recentPoints[i].velocity * weight;
      totalWeight += weight;
    }

    if (totalWeight > 0) {
      avgVelocity = avgVelocity / totalWeight;
    }

    // Predict trajectory using physics
    final List<Offset> predictedPath = [];
    final lastPoint = points.last;

    double currentX = lastPoint.position.dx;
    double currentY = lastPoint.position.dy;
    double velocityX = avgVelocity.dx;
    double velocityY = avgVelocity.dy;

    const double timeStep = 0.016; // ~60 FPS
    const int maxSteps = 180; // ~3 seconds prediction

    bool willEnterHoop = false;
    Offset? entryPoint;

    for (int step = 0; step < maxSteps; step++) {
      // Apply gravity (convert to pixels)
      velocityY += (gravity * pixelsPerMeter * timeStep);

      // Update position
      currentX += velocityX * timeStep;
      currentY += velocityY * timeStep;

      final currentPos = Offset(currentX, currentY);
      predictedPath.add(currentPos);

      // Check if ball enters hoop area
      final distanceToHoop = (currentPos - hoopPosition).distance;
      if (distanceToHoop < 30 && !willEnterHoop) {
        // Within hoop radius
        willEnterHoop = true;
        entryPoint = currentPos;
      }

      // Stop if ball goes too far down (ground level)
      if (currentY > videoDisplayHeight(1.0) + 100) {
        break;
      }
    }

    // Calculate confidence based on trajectory consistency
    double confidence = _calculateTrajectoryConfidence(recentPoints);

    return PredictionResult(
      predictedPath,
      willEnterHoop,
      confidence,
      entryPoint,
    );
  }

  double _calculateTrajectoryConfidence(List<TrajectoryPoint> points) {
    if (points.length < 3) return 0.0;

    // Calculate velocity consistency
    double velocityVariation = 0.0;
    for (int i = 1; i < points.length - 1; i++) {
      final vel1 = points[i].velocity;
      final vel2 = points[i + 1].velocity;
      velocityVariation += (vel1 - vel2).distance;
    }

    // Lower variation = higher confidence
    final avgVariation = velocityVariation / (points.length - 2);
    return max(0.0, min(1.0, 1.0 - (avgVariation / 100.0)));
  }

  void _drawPredictedPath(
    Canvas canvas,
    PredictionResult prediction,
    Color baseColor,
  ) {
    if (prediction.predictedPath.length < 2) return;

    final pathPaint = Paint()
      ..color = baseColor.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Draw predicted trajectory
    for (int i = 0; i < prediction.predictedPath.length - 1; i++) {
      // Fade out the path over distance
      final alpha =
          (1.0 - (i / prediction.predictedPath.length.toDouble())) * 0.7;
      pathPaint.color = baseColor.withOpacity(alpha);

      canvas.drawLine(
        prediction.predictedPath[i],
        prediction.predictedPath[i + 1],
        pathPaint,
      );
    }

    // Draw entry point if ball will enter hoop
    if (prediction.willEnterHoop && prediction.hoopEntryPoint != null) {
      final entryPaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.fill;

      canvas.drawCircle(prediction.hoopEntryPoint!, 8, entryPaint);

      // Draw success indicator
      final textPainter = TextPainter(textDirection: TextDirection.ltr);
      textPainter.text = TextSpan(
        text: '✓ SHOT ${(prediction.confidence * 100).toStringAsFixed(0)}%',
        style: TextStyle(
          color: Colors.green,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black87,
        ),
      );
      textPainter.layout();

      final textOffset = Offset(
        prediction.hoopEntryPoint!.dx - textPainter.width / 2,
        prediction.hoopEntryPoint!.dy - 30,
      );
      textPainter.paint(canvas, textOffset);
    }
  }

  List<Offset> _calculateOptimalShotPath(
    Offset startPosition,
    Offset hoopPosition,
  ) {
    // Calculate optimal launch angle and velocity for perfect shot
    final dx = hoopPosition.dx - startPosition.dx;
    final dy = hoopPosition.dy - startPosition.dy;

    // Use physics to calculate optimal trajectory
    const double optimalAngle = pi / 4; // 45 degrees as starting point

    // Calculate required initial velocity
    final distance = sqrt(dx * dx + dy * dy);
    final requiredVelocity = sqrt(gravity * pixelsPerMeter * distance);

    final velocityX = requiredVelocity * cos(optimalAngle) * (dx > 0 ? 1 : -1);
    final velocityY =
        -requiredVelocity * sin(optimalAngle); // Negative for upward

    // Generate optimal path
    final List<Offset> optimalPath = [];
    double currentX = startPosition.dx;
    double currentY = startPosition.dy;
    double velX = velocityX;
    double velY = velocityY;

    const double timeStep = 0.016;

    for (int step = 0; step < 120; step++) {
      optimalPath.add(Offset(currentX, currentY));

      // Apply physics
      velY += (gravity * pixelsPerMeter * timeStep);
      currentX += velX * timeStep;
      currentY += velY * timeStep;

      // Stop when we reach or pass the hoop
      if ((currentX - hoopPosition.dx).abs() < 5 &&
          currentY >= hoopPosition.dy) {
        break;
      }
    }

    return optimalPath;
  }

  void _drawOptimalPath(Canvas canvas, List<Offset> optimalPath) {
    if (optimalPath.length < 2) return;

    final optimalPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw dashed optimal trajectory
    for (int i = 0; i < optimalPath.length - 1; i++) {
      if (i % 2 == 0) {
        // Draw every other segment for dashed effect
        canvas.drawLine(optimalPath[i], optimalPath[i + 1], optimalPaint);
      }
    }

    // Add label
    if (optimalPath.isNotEmpty) {
      final textPainter = TextPainter(textDirection: TextDirection.ltr);
      textPainter.text = TextSpan(
        text: 'OPTIMAL SHOT',
        style: TextStyle(
          color: Colors.yellow,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black54,
        ),
      );
      textPainter.layout();

      final midPoint = optimalPath[optimalPath.length ~/ 2];
      final textOffset = Offset(
        midPoint.dx - textPainter.width / 2,
        midPoint.dy - 20,
      );
      textPainter.paint(canvas, textOffset);
    }
  }

  Color _getTrackColor(int trackId) {
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.cyan,
      Colors.pink,
      Colors.yellow,
    ];
    return colors[trackId % colors.length];
  }

  @override
  bool shouldRepaint(DetectionPainter oldDelegate) {
    // // Only repaint if current frame detections actually changed
    if (currentFrame != oldDelegate.currentFrame) {
      // Check if the detections for this specific frame are different
      final currentDetections = currentFrame < allFrames.length
          ? allFrames[currentFrame].detections
          : <Detection>[];
      final oldDetections =
          oldDelegate.currentFrame < oldDelegate.allFrames.length
          ? oldDelegate.allFrames[oldDelegate.currentFrame].detections
          : <Detection>[];

      if (currentDetections.length != oldDetections.length) return true;

      // Only repaint if detection positions/confidence actually changed
      for (int i = 0; i < currentDetections.length; i++) {
        if (i >= oldDetections.length ||
            currentDetections[i].bbox != oldDetections[i].bbox ||
            currentDetections[i].confidence != oldDetections[i].confidence) {
          return true;
        }
      }
    }

    // Always repaint for size changes
    return videoSize != oldDelegate.videoSize ||
        widgetSize != oldDelegate.widgetSize ||
        aspectRatio != oldDelegate.aspectRatio;
  }
}

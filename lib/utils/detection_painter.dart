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
  final bool calculateInFrameReference;

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
    this.calculateInFrameReference = false,
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
    // Get ball trajectories with better filtering and grouping
    final ballTrajectories = _getBallTrajectoriesForDrawing(
      scaleX,
      scaleY,
      offsetX,
      offsetY,
    );

    for (final entry in ballTrajectories.entries) {
      final trackId = entry.key;
      final points = entry.value;

      if (points.length < 2) continue;

      final color = _getTrackColor(trackId);

      // Draw trajectory path with gradient effect
      _drawTrajectoryPath(canvas, points, color);

      // Draw trajectory points
      _drawTrajectoryPoints(canvas, points, color);
    }
  }

  Map<int, List<Offset>> _getBallTrajectoriesForDrawing(
    double scaleX,
    double scaleY,
    double offsetX,
    double offsetY,
  ) {
    Map<int, List<Offset>> trajectories = {};

    // Show trajectory for a reasonable time window (last 3 seconds or 90 frames)
    final int maxFramesToShow = 90;
    int startFrame, endFrame;

    if (calculateInFrameReference) {
      // Frame-of-reference mode: only show trajectory up to current frame
      startFrame = (currentFrame - maxFramesToShow).clamp(0, currentFrame);
      endFrame = currentFrame;
    } else {
      // Real-time mode: show full trajectory window
      startFrame = (currentFrame - maxFramesToShow).clamp(0, currentFrame);
      endFrame = currentFrame;
    }

    // Collect ball positions in chronological order
    for (int i = startFrame; i <= endFrame && i < allFrames.length; i++) {
      final frame = allFrames[i];

      // Only process ball detections
      final ballDetections = frame.detections
          .where((d) => d.label.toLowerCase() == "ball")
          .toList();

      for (final detection in ballDetections) {
        final centerX = (detection.bbox.centerX * scaleX) + offsetX;
        final centerY = (detection.bbox.centerY * scaleY) + offsetY;
        final position = Offset(centerX, centerY);

        // Group by track ID, but also validate the trajectory makes sense
        final trackId = detection.trackId;

        trajectories.putIfAbsent(trackId, () => []);
        final currentTrajectory = trajectories[trackId]!;

        // Only add point if it's reasonable (not a huge jump)
        if (currentTrajectory.isEmpty ||
            _isReasonableMovement(currentTrajectory.last, position)) {
          currentTrajectory.add(position);
        } else {
          // If there's a huge jump, start a new trajectory
          trajectories[trackId] = [position];
        }
      }
    }

    // Clean up short or invalid trajectories
    trajectories.removeWhere((trackId, points) => points.length < 3);

    return trajectories;
  }

  bool _isReasonableMovement(Offset lastPosition, Offset newPosition) {
    final distance = (newPosition - lastPosition).distance;
    // Maximum reasonable movement between frames (adjust based on your video resolution/framerate)
    const double maxMovement = 200.0; // pixels
    return distance < maxMovement;
  }

  void _drawTrajectoryPath(
    Canvas canvas,
    List<Offset> points,
    Color baseColor,
  ) {
    if (points.length < 2) return;

    // Create smooth interpolated path
    final interpolatedPoints = _createSmoothTrajectory(points);

    if (interpolatedPoints.length < 2) return;

    // Create smooth path using splines
    final path = _createSplinePath(interpolatedPoints);

    // Draw the path with gradient effect
    _drawGradientPath(canvas, path, interpolatedPoints, baseColor);
  }

  List<Offset> _createSmoothTrajectory(List<Offset> originalPoints) {
    if (originalPoints.length < 2) return originalPoints;

    List<Offset> smoothPoints = [];

    // Add the first point
    smoothPoints.add(originalPoints.first);

    // Interpolate between consecutive points
    for (int i = 0; i < originalPoints.length - 1; i++) {
      final current = originalPoints[i];
      final next = originalPoints[i + 1];

      // Calculate number of interpolation steps based on distance
      final distance = (next - current).distance;
      final steps = (distance / 12.0).ceil().clamp(
        2,
        10,
      ); // 12 pixels per step, max 10 steps

      // Add interpolated points between current and next
      for (int step = 1; step <= steps; step++) {
        final t = step / steps;

        // Use smooth interpolation with physics-based easing
        final smoothT = _smoothStep(t);

        final interpolated = Offset(
          current.dx + (next.dx - current.dx) * smoothT,
          current.dy + (next.dy - current.dy) * smoothT,
        );

        // Only add if it's the last step or if it's reasonably different from the last point
        if (step == steps ||
            (interpolated - smoothPoints.last).distance > 3.0) {
          smoothPoints.add(interpolated);
        }
      }
    }

    return smoothPoints;
  }

  double _smoothStep(double t) {
    // Smooth step function for more natural ball movement
    return t * t * (3.0 - 2.0 * t);
  }

  Path _createSplinePath(List<Offset> points) {
    if (points.length < 2) return Path();

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);

    if (points.length == 2) {
      path.lineTo(points.last.dx, points.last.dy);
      return path;
    }

    // Use catmull-rom spline for natural ball trajectory
    for (int i = 1; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i < points.length - 2 ? points[i + 2] : points[i + 1];

      // Create smooth curve segment
      _addCatmullRomSegment(path, p0, p1, p2, p3);
    }

    return path;
  }

  void _addCatmullRomSegment(
    Path path,
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
  ) {
    const int segments = 8; // Number of curve segments

    for (int i = 1; i <= segments; i++) {
      final t = i / segments;
      final point = _catmullRomPoint(p0, p1, p2, p3, t);
      path.lineTo(point.dx, point.dy);
    }
  }

  Offset _catmullRomPoint(
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
    double t,
  ) {
    final t2 = t * t;
    final t3 = t2 * t;

    final x =
        0.5 *
        ((2.0 * p1.dx) +
            (-p0.dx + p2.dx) * t +
            (2.0 * p0.dx - 5.0 * p1.dx + 4.0 * p2.dx - p3.dx) * t2 +
            (-p0.dx + 3.0 * p1.dx - 3.0 * p2.dx + p3.dx) * t3);

    final y =
        0.5 *
        ((2.0 * p1.dy) +
            (-p0.dy + p2.dy) * t +
            (2.0 * p0.dy - 5.0 * p1.dy + 4.0 * p2.dy - p3.dy) * t2 +
            (-p0.dy + 3.0 * p1.dy - 3.0 * p2.dy + p3.dy) * t3);

    return Offset(x, y);
  }

  void _drawGradientPath(
    Canvas canvas,
    Path path,
    List<Offset> points,
    Color baseColor,
  ) {
    // Draw multiple path strokes with varying opacity for gradient effect
    final totalPoints = points.length;

    // Create segments with different opacities for smooth gradient
    for (int segment = 0; segment < 6; segment++) {
      final startRatio = segment / 6.0;
      final endRatio = (segment + 1) / 6.0;

      final startIndex = (startRatio * totalPoints).floor();
      final endIndex = (endRatio * totalPoints).ceil().clamp(
        startIndex + 1,
        totalPoints,
      );

      if (startIndex >= endIndex - 1) continue;

      // Create segment path
      final segmentPath = Path();
      if (startIndex < points.length) {
        segmentPath.moveTo(points[startIndex].dx, points[startIndex].dy);

        for (int i = startIndex + 1; i < endIndex && i < points.length; i++) {
          segmentPath.lineTo(points[i].dx, points[i].dy);
        }

        // Calculate opacity based on segment position (newer segments are more opaque)
        final opacity = (0.15 + (segment / 6.0) * 0.65).clamp(0.0, 0.8);
        final strokeWidth = 1.5 + (segment / 6.0) * 2.5; // Thicker toward end

        final paint = Paint()
          ..color = baseColor.withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        canvas.drawPath(segmentPath, paint);
      }
    }
  }

  void _drawTrajectoryPoints(
    Canvas canvas,
    List<Offset> points,
    Color baseColor,
  ) {
    // Only draw key trajectory points (every 4th point) to avoid cluttering with interpolated points
    for (int i = 0; i < points.length; i += 4) {
      final progress = i / (points.length - 1);
      final opacity = (0.3 + (progress * 0.5)).clamp(0.0, 0.7);
      final radius =
          1.5 + (progress * 2.5); // Larger points for recent positions

      // Main point
      final paint = Paint()
        ..color = baseColor.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(points[i], radius, paint);

      // Add subtle white outline for better visibility
      final outlinePaint = Paint()
        ..color = Colors.white.withOpacity(opacity * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;

      canvas.drawCircle(points[i], radius, outlinePaint);
    }

    // Always draw the most recent point more prominently
    if (points.isNotEmpty) {
      final lastPoint = points.last;

      // Large current position indicator
      final currentPaint = Paint()
        ..color = baseColor.withOpacity(0.9)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(lastPoint, 4.0, currentPaint);

      // Bright outline
      final currentOutlinePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawCircle(lastPoint, 4.0, currentOutlinePaint);

      // Small inner highlight
      final highlightPaint = Paint()
        ..color = Colors.white.withOpacity(0.8)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(lastPoint, 1.5, highlightPaint);
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
    // Only show predictions if enabled
    if (showEstimatedPath != true) return;

    // Get current hoop position (adaptive detection)
    final hoopPosition = _detectHoopPosition(scaleX, scaleY, offsetX, offsetY);
    if (hoopPosition == null) return;

    // Draw hoop
    _drawHoop(canvas, hoopPosition);

    // Get current ball trajectories for prediction (only recent ones)
    final ballTrajectories = _getBallTrajectoriesForDrawing(
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

      // Convert Offset points to TrajectoryPoint for prediction
      final trajectoryData = _convertToTrajectoryPoints(
        trackId,
        trajectoryPoints,
      );

      if (trajectoryData.length < 3) continue;

      // Predict trajectory based on calculation mode
      final prediction = calculateInFrameReference
          ? _predictBallTrajectoryFromFrame(trajectoryData, hoopPosition)
          : _predictBallTrajectory(trajectoryData, hoopPosition);

      // Draw predicted path
      _drawPredictedPath(canvas, prediction, _getTrackColor(trackId));

      // Draw optimal shot path from current ball position
      if (trajectoryData.isNotEmpty) {
        final currentPosition = trajectoryData.last.position;
        final optimalPath = _calculateOptimalShotPath(
          currentPosition,
          hoopPosition,
        );
        _drawOptimalPath(canvas, optimalPath);
      }
    }
  }

  List<TrajectoryPoint> _convertToTrajectoryPoints(
    int trackId,
    List<Offset> positions,
  ) {
    if (positions.length < 2) return [];

    List<TrajectoryPoint> trajectoryPoints = [];

    // Create trajectory points with calculated velocities
    for (int i = 0; i < positions.length; i++) {
      final position = positions[i];
      final timestamp =
          i * (1.0 / 30.0); // Assume 30fps, adjust based on your video

      Offset velocity = Offset.zero;
      if (i > 0) {
        final dt = 1.0 / 30.0; // Frame interval
        final dx = position.dx - positions[i - 1].dx;
        final dy = position.dy - positions[i - 1].dy;
        velocity = Offset(dx / dt, dy / dt);
      }

      trajectoryPoints.add(TrajectoryPoint(position, timestamp, velocity));
    }

    return trajectoryPoints;
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

    return null;
  }

  double videoDisplayWidth(double scaleX) => videoSize.width * scaleX;
  double videoDisplayHeight(double scaleY) => videoSize.height * scaleY;

  void _drawHoop(Canvas canvas, Offset hoopPosition) {
    final hoopPaint = Paint()
      ..color = const Color(0xFF1565C0)
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

  PredictionResult _predictBallTrajectoryFromFrame(
    List<TrajectoryPoint> points,
    Offset hoopPosition,
  ) {
    if (points.length < 3) {
      return PredictionResult([], false, 0.0, null);
    }

    // Frame-of-reference calculation: Use the trajectory data at the current frame position
    // This provides a stable calculation that doesn't change as the video plays
    final currentFramePoint = points.last;

    // Use more points for better velocity estimation in frame mode
    final analysisPoints = points.length > 8
        ? points.sublist(points.length - 8)
        : points;

    // Calculate velocity using polynomial fitting for better accuracy
    Offset frameVelocity = _calculateFrameBasedVelocity(analysisPoints);

    // Predict trajectory using physics with frame-based velocity
    final List<Offset> predictedPath = [];

    double currentX = currentFramePoint.position.dx;
    double currentY = currentFramePoint.position.dy;
    double velocityX = frameVelocity.dx;
    double velocityY = frameVelocity.dy;

    const double timeStep = 0.016; // ~60 FPS
    const int maxSteps = 240; // ~4 seconds prediction for frame mode

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

    // Higher confidence for frame-based calculations due to stability
    double confidence = _calculateTrajectoryConfidence(analysisPoints) * 1.2;
    confidence = confidence.clamp(0.0, 1.0);

    return PredictionResult(
      predictedPath,
      willEnterHoop,
      confidence,
      entryPoint,
    );
  }

  Offset _calculateFrameBasedVelocity(List<TrajectoryPoint> points) {
    if (points.length < 3) return Offset.zero;

    // Use weighted average with emphasis on recent points
    double totalWeightX = 0.0, totalWeightY = 0.0;
    double weightedVelX = 0.0, weightedVelY = 0.0;

    for (int i = 1; i < points.length; i++) {
      final dt = points[i].timestamp - points[i - 1].timestamp;
      if (dt <= 0) continue;

      final dx = points[i].position.dx - points[i - 1].position.dx;
      final dy = points[i].position.dy - points[i - 1].position.dy;

      final velX = dx / dt;
      final velY = dy / dt;

      // Weight more recent velocities higher
      final weight = i.toDouble() / points.length;

      weightedVelX += velX * weight;
      weightedVelY += velY * weight;
      totalWeightX += weight;
      totalWeightY += weight;
    }

    if (totalWeightX > 0 && totalWeightY > 0) {
      return Offset(weightedVelX / totalWeightX, weightedVelY / totalWeightY);
    }

    return Offset.zero;
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

    // Draw optimal trajectory with a more visible dashed pattern
    for (int i = 0; i < optimalPath.length - 1; i++) {
      final progress = i / (optimalPath.length - 1);

      // Create dashed effect with varying opacity
      if (i % 3 != 2) {
        // Draw 2 segments, skip 1 for dash effect
        final paint = Paint()
          ..color = Colors.yellow.withOpacity(0.7 + (progress * 0.2))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(optimalPath[i], optimalPath[i + 1], paint);
      }
    }

    // Draw optimal path points
    for (int i = 0; i < optimalPath.length; i += 4) {
      // Show every 4th point
      final paint = Paint()
        ..color = const Color(0xFF1565C0).withOpacity(0.8)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(optimalPath[i], 3.0, paint);

      // White outline for visibility
      final outlinePaint = Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawCircle(optimalPath[i], 3.0, outlinePaint);
    }

    // Add label at the start of the optimal path
    if (optimalPath.isNotEmpty) {
      final textPainter = TextPainter(textDirection: TextDirection.ltr);
      textPainter.text = TextSpan(
        text: '🎯 OPTIMAL SHOT',
        style: TextStyle(
          color: Colors.yellow,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              blurRadius: 2.0,
              color: Colors.black.withOpacity(0.8),
              offset: Offset(1.0, 1.0),
            ),
          ],
        ),
      );
      textPainter.layout();

      // Place label near the start of the optimal path
      final startPoint = optimalPath.first;
      final textOffset = Offset(startPoint.dx + 10, startPoint.dy - 25);
      textPainter.paint(canvas, textOffset);
    }
  }

  Color _getTrackColor(int trackId) {
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      const Color(0xFF1565C0),
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

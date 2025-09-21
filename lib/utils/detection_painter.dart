import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:hooplab/models/clip.dart';

class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final Size videoSize;
  final Size widgetSize;
  final double aspectRatio;
  final List<FrameData> allFrames;
  final int currentFrame;
  final bool showTrajectories;
  final bool? showEstimatedPath;

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

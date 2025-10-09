import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';

class TrajectoryPoint {
  final Offset position;
  final double timestamp;

  TrajectoryPoint({required this.position, required this.timestamp});
}

class ShotAnalysisResult {
  final double arcHeight;
  final double entryAngle;
  final double shotDistance;
  final Offset? releasePoint;
  final Offset? rimContact;
  final ShotQuality quality;
  final List<String> improvementTips;

  ShotAnalysisResult({
    required this.arcHeight,
    required this.entryAngle,
    required this.shotDistance,
    this.releasePoint,
    this.rimContact,
    required this.quality,
    required this.improvementTips,
  });
}

enum ShotQuality { excellent, good, average, needsWork, poor }

class ShotAnalyzer {
  static const double optimalArcHeight = 11.0; // feet (for free throw distance)
  static const double optimalEntryAngle = 45.0; // degrees
  static const double rimHeight = 10.0; // feet
  static const double pixelsPerFoot =
      30.0; // Rough conversion - adjust based on your video scale

  /// Analyzes a complete shot trajectory and provides feedback
  static ShotAnalysisResult analyzeShotTrajectory({
    required List<FrameData> frames,
    Offset? hoopPosition,
  }) {
    // Extract ball trajectory points with timestamps
    List<TrajectoryPoint> trajectoryPoints = [];

    for (final frame in frames) {
      final ballDetections = frame.detections
          .where((d) => d.label.toLowerCase().contains('ball'))
          .toList();

      if (ballDetections.isNotEmpty) {
        final ball = ballDetections.first;
        trajectoryPoints.add(
          TrajectoryPoint(
            position: Offset(ball.bbox.centerX, ball.bbox.centerY),
            timestamp: frame.timestamp,
          ),
        );
      }
    }

    if (trajectoryPoints.length < 3) {
      return ShotAnalysisResult(
        arcHeight: 0,
        entryAngle: 0,
        shotDistance: 0,
        quality: ShotQuality.poor,
        improvementTips: ['Not enough trajectory data to analyze'],
      );
    }

    // Detect and extract the primary shot
    final primaryShot = _extractPrimaryShot(trajectoryPoints, hoopPosition);

    if (primaryShot.length < 3) {
      return ShotAnalysisResult(
        arcHeight: 0,
        entryAngle: 0,
        shotDistance: 0,
        quality: ShotQuality.poor,
        improvementTips: ['Primary shot trajectory too short to analyze'],
      );
    }

    final ballPoints = primaryShot.map((tp) => tp.position).toList();

    // Find hoop position if not provided
    hoopPosition ??= _findHoopPosition(frames) ?? ballPoints.last;

    // Calculate key metrics
    final arcHeight = _calculateArcHeight(ballPoints);
    final entryAngle = _calculateEntryAngle(ballPoints, hoopPosition);
    final shotDistance = _calculateShotDistance(ballPoints.first, hoopPosition);
    final releasePoint = ballPoints.first;
    final rimContact = _findRimContact(ballPoints, hoopPosition);

    // Determine shot quality and generate tips
    final quality = _assessShotQuality(arcHeight, entryAngle);
    final tips = _generateImprovementTips(
      arcHeight,
      entryAngle,
      ballPoints,
      hoopPosition,
    );

    return ShotAnalysisResult(
      arcHeight: arcHeight,
      entryAngle: entryAngle,
      shotDistance: shotDistance,
      releasePoint: releasePoint,
      rimContact: rimContact,
      quality: quality,
      improvementTips: tips,
    );
  }

  /// Calculate the peak height of the ball trajectory
  static double _calculateArcHeight(List<Offset> ballPoints) {
    if (ballPoints.isEmpty) return 0;

    // Find the highest point (lowest Y value since Y=0 is top of screen)
    double highestPoint = ballPoints.first.dy;
    double lowestPoint = ballPoints.first.dy;

    for (final point in ballPoints) {
      if (point.dy < highestPoint) highestPoint = point.dy;
      if (point.dy > lowestPoint) lowestPoint = point.dy;
    }

    // Convert pixel difference to approximate feet
    final arcHeightPixels = lowestPoint - highestPoint;
    final arcHeightFeet = arcHeightPixels / pixelsPerFoot;

    return arcHeightFeet.clamp(0, 25); // Reasonable bounds
  }

  /// Calculate the entry angle at which the ball approaches the rim
  static double _calculateEntryAngle(
    List<Offset> ballPoints,
    Offset rimPosition,
  ) {
    if (ballPoints.length < 3) return 0;

    // Use the last few points to calculate approach angle
    final approachPoints = ballPoints.length >= 5
        ? ballPoints.sublist(ballPoints.length - 5)
        : ballPoints.sublist(ballPoints.length - 2);

    if (approachPoints.length < 2) return 0;

    // Calculate the trajectory vector approaching the rim
    final start = approachPoints[approachPoints.length - 2];
    final end = approachPoints.last;

    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;

    // Calculate angle (positive Y is downward)
    final angleRadians = atan2(
      dy,
      dx.abs(),
    ); // Use absolute dx for consistent angle measurement
    final angleDegrees = angleRadians * (180 / pi);

    return angleDegrees.clamp(0, 90);
  }

  /// Calculate the horizontal distance of the shot
  static double _calculateShotDistance(Offset startPoint, Offset endPoint) {
    final pixelDistance = (startPoint.dx - endPoint.dx).abs();
    return pixelDistance / pixelsPerFoot; // Convert to feet
  }

  /// Find rim contact point (closest point to hoop position)
  static Offset? _findRimContact(List<Offset> ballPoints, Offset hoopPosition) {
    if (ballPoints.isEmpty) return null;

    Offset? closestPoint;
    double minDistance = double.infinity;

    for (final point in ballPoints) {
      final distance = (point - hoopPosition).distance;
      if (distance < minDistance) {
        minDistance = distance;
        closestPoint = point;
      }
    }

    return closestPoint;
  }

  /// Find hoop position from frame detections
  static Offset? _findHoopPosition(List<FrameData> frames) {
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

  /// Find all hoop positions detected in frames
  static List<Offset> findAllHoops(List<FrameData> frames) {
    final Map<String, Offset> uniqueHoops = {};

    for (final frame in frames) {
      final hoopDetections = frame.detections
          .where(
            (d) =>
                d.label.toLowerCase().contains('hoop') ||
                d.label.toLowerCase().contains('rim') ||
                d.label.toLowerCase().contains('basket'),
          )
          .toList();

      for (final hoop in hoopDetections) {
        final position = Offset(hoop.bbox.centerX, hoop.bbox.centerY);

        // Cluster nearby hoops (same hoop across frames)
        bool isSameAsExisting = false;
        for (final existingPos in uniqueHoops.values) {
          if ((position - existingPos).distance < 100) {
            // Within 100px = same hoop
            isSameAsExisting = true;
            break;
          }
        }

        if (!isSameAsExisting) {
          uniqueHoops['hoop_${uniqueHoops.length}'] = position;
        }
      }
    }

    return uniqueHoops.values.toList();
  }

  /// Filter ball trajectory to only include points near the target hoop
  static List<FrameData> filterFramesByHoopROI(
    List<FrameData> frames,
    Offset targetHoop,
    double roiRadius,
  ) {
    return frames.where((frame) {
      final ballDetections = frame.detections
          .where((d) => d.label.toLowerCase().contains('ball'))
          .toList();

      if (ballDetections.isEmpty) return false;

      final ball = ballDetections.first;
      final ballPosition = Offset(ball.bbox.centerX, ball.bbox.centerY);

      // Check if ball is within ROI of target hoop
      return (ballPosition - targetHoop).distance <= roiRadius;
    }).toList();
  }

  /// Determine which hoop a trajectory is targeting based on proximity
  static Offset? selectTargetHoop(
    List<Offset> allHoops,
    List<FrameData> trajectoryFrames,
  ) {
    if (allHoops.isEmpty || trajectoryFrames.isEmpty) return null;
    if (allHoops.length == 1) return allHoops.first;

    // Find which hoop the ball gets closest to
    double minDistance = double.infinity;
    Offset? targetHoop;

    for (final hoopPos in allHoops) {
      for (final frame in trajectoryFrames) {
        final ballDetections = frame.detections
            .where((d) => d.label.toLowerCase().contains('ball'))
            .toList();

        if (ballDetections.isNotEmpty) {
          final ball = ballDetections.first;
          final ballPos = Offset(ball.bbox.centerX, ball.bbox.centerY);
          final distance = (ballPos - hoopPos).distance;

          if (distance < minDistance) {
            minDistance = distance;
            targetHoop = hoopPos;
          }
        }
      }
    }

    return targetHoop;
  }

  /// Assess overall shot quality based on metrics
  static ShotQuality _assessShotQuality(double arcHeight, double entryAngle) {
    int score = 0;

    // Arc height scoring (0-2 points)
    if (arcHeight >= 9 && arcHeight <= 13) {
      score += 2; // Excellent arc
    } else if (arcHeight >= 7 && arcHeight <= 15) {
      score += 1; // Good arc
    }

    // Entry angle scoring (0-2 points)
    if (entryAngle >= 40 && entryAngle <= 55) {
      score += 2; // Excellent entry angle
    } else if (entryAngle >= 30 && entryAngle <= 65) {
      score += 1; // Good entry angle
    }

    // Convert score to quality
    switch (score) {
      case 4:
        return ShotQuality.excellent;
      case 3:
        return ShotQuality.good;
      case 2:
        return ShotQuality.average;
      case 1:
        return ShotQuality.needsWork;
      default:
        return ShotQuality.poor;
    }
  }

  /// Generate specific improvement tips based on analysis
  static List<String> _generateImprovementTips(
    double arcHeight,
    double entryAngle,
    List<Offset> ballPoints,
    Offset hoopPosition,
  ) {
    List<String> tips = [];

    // Arc height feedback
    if (arcHeight < 8) {
      tips.add(
        "🔺 Your shot is too flat. Try releasing the ball at a higher angle (45° or more).",
      );
      tips.add("💪 Use more leg drive to generate upward momentum.");
    } else if (arcHeight > 15) {
      tips.add("🔻 Your shot is too high. Lower your release angle slightly.");
      tips.add("🎯 Focus on shooting through the rim, not over it.");
    } else if (arcHeight >= 9 && arcHeight <= 13) {
      tips.add("✅ Excellent arc height! Keep this consistency.");
    }

    // Entry angle feedback
    if (entryAngle < 35) {
      tips.add(
        "📐 Your entry angle is too flat (${entryAngle.toStringAsFixed(1)}°). Aim for 45°+ for better rim coverage.",
      );
      tips.add("⬆️ Increase your shooting arc to get a steeper entry angle.");
    } else if (entryAngle > 60) {
      tips.add(
        "📐 Your entry angle is too steep (${entryAngle.toStringAsFixed(1)}°). Try a slightly flatter trajectory.",
      );
    } else {
      tips.add(
        "✅ Great entry angle (${entryAngle.toStringAsFixed(1)}°)! Perfect rim approach.",
      );
    }

    // Direction feedback (basic left/right analysis)
    final lastPoint = ballPoints.last;
    final horizontalMiss = (lastPoint.dx - hoopPosition.dx).abs();

    if (horizontalMiss > 20) {
      // Significant miss left or right
      if (lastPoint.dx < hoopPosition.dx) {
        tips.add(
          "⬅️ Shot drifted left. Check your shooting hand alignment and follow-through.",
        );
      } else {
        tips.add(
          "➡️ Shot drifted right. Ensure your elbow is under the ball at release.",
        );
      }
      tips.add("🎯 Focus on keeping your shooting hand square to the rim.");
    }

    // If no issues found, provide encouragement
    if (tips.isEmpty || tips.every((tip) => tip.startsWith("✅"))) {
      tips.add(
        "🏀 Great shot mechanics! Keep practicing to maintain this consistency.",
      );
    }

    return tips;
  }

  /// Extract the primary shot from trajectory data, filtering out multiple shots
  static List<TrajectoryPoint> _extractPrimaryShot(
    List<TrajectoryPoint> trajectoryPoints,
    Offset? hoopPosition,
  ) {
    if (trajectoryPoints.length < 3) return trajectoryPoints;

    // Detect shot breaks by looking for sudden position jumps
    List<List<TrajectoryPoint>> shotSegments = [];
    List<TrajectoryPoint> currentSegment = [trajectoryPoints.first];

    for (int i = 1; i < trajectoryPoints.length; i++) {
      final prev = trajectoryPoints[i - 1];
      final current = trajectoryPoints[i];

      // Calculate distance between consecutive points
      final distance = (current.position - prev.position).distance;
      final timeDiff = current.timestamp - prev.timestamp;

      // If the ball jumps too far too quickly, it's likely a new shot
      final speed = timeDiff > 0 ? distance / timeDiff : 0;

      if (distance > 150 || speed > 1000) {
        // Threshold for detecting shot break
        // End current segment and start a new one
        if (currentSegment.length > 2) {
          shotSegments.add(List.from(currentSegment));
        }
        currentSegment = [current];
      } else {
        currentSegment.add(current);
      }
    }

    // Add the last segment
    if (currentSegment.length > 2) {
      shotSegments.add(currentSegment);
    }

    if (shotSegments.isEmpty) {
      return trajectoryPoints; // Fallback to original if no segments found
    }

    // Find the best shot segment (longest or closest to hoop)
    List<TrajectoryPoint> bestShot = shotSegments.first;

    if (hoopPosition != null && shotSegments.length > 1) {
      // Choose the segment that ends closest to the hoop
      double bestDistance = double.infinity;

      for (final segment in shotSegments) {
        if (segment.isNotEmpty) {
          final endDistance = (segment.last.position - hoopPosition).distance;
          if (endDistance < bestDistance) {
            bestDistance = endDistance;
            bestShot = segment;
          }
        }
      }
    } else {
      // Choose the longest segment
      for (final segment in shotSegments) {
        if (segment.length > bestShot.length) {
          bestShot = segment;
        }
      }
    }

    debugPrint(
      '🏀 Detected ${shotSegments.length} shot segments, using segment with ${bestShot.length} points',
    );
    return bestShot;
  }

  /// Get a color representing shot quality
  static Color getQualityColor(ShotQuality quality) {
    switch (quality) {
      case ShotQuality.excellent:
        return Colors.green;
      case ShotQuality.good:
        return Colors.lightGreen;
      case ShotQuality.average:
        return const Color(0xFF1565C0);
      case ShotQuality.needsWork:
        return Colors.deepOrange;
      case ShotQuality.poor:
        return Colors.red;
    }
  }

  /// Get a text description of shot quality
  static String getQualityText(ShotQuality quality) {
    switch (quality) {
      case ShotQuality.excellent:
        return "Excellent";
      case ShotQuality.good:
        return "Good";
      case ShotQuality.average:
        return "Average";
      case ShotQuality.needsWork:
        return "Needs Work";
      case ShotQuality.poor:
        return "Poor";
    }
  }
}

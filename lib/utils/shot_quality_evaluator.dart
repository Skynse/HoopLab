import 'dart:math';
import 'package:flutter/material.dart';

/// Evaluates shot quality based on form/technique, not whether it went in
class ShotQualityEvaluator {
  /// Calculate shot quality score (0-100) based on multiple factors
  /// Higher score = better shooting form/technique
  static ShotQualityResult evaluateShotQuality({
    required List<Offset> ballTrajectory,
    required Offset hoopPosition,
    double hoopRadius = 30.0,
  }) {
    if (ballTrajectory.length < 5) {
      return ShotQualityResult(
        overallScore: 0.0,
        arcScore: 0.0,
        releaseAngleScore: 0.0,
        distanceScore: 0.0,
        consistencyScore: 0.0,
        feedback: 'Not enough data to evaluate shot',
      );
    }

    // 1. Arc Quality (0-30 points) - Does the ball have a good arc?
    final arcScore = _evaluateArc(ballTrajectory, hoopPosition);

    // 2. Release Angle (0-25 points) - Is the initial trajectory angle good?
    final releaseAngleScore = _evaluateReleaseAngle(ballTrajectory);

    // 3. Distance to Target (0-25 points) - How close did it get to the hoop?
    final distanceScore = _evaluateDistanceToHoop(
      ballTrajectory,
      hoopPosition,
      hoopRadius,
    );

    // 4. Trajectory Consistency (0-20 points) - Is the arc smooth?
    final consistencyScore = _evaluateTrajectoryConsistency(ballTrajectory);

    // Overall score out of 100
    final overallScore =
        (arcScore + releaseAngleScore + distanceScore + consistencyScore).clamp(
          0.0,
          100.0,
        );

    // Generate feedback
    final feedback = _generateFeedback(
      overallScore: overallScore,
      arcScore: arcScore,
      releaseAngleScore: releaseAngleScore,
      distanceScore: distanceScore,
      consistencyScore: consistencyScore,
    );

    return ShotQualityResult(
      overallScore: overallScore,
      arcScore: arcScore,
      releaseAngleScore: releaseAngleScore,
      distanceScore: distanceScore,
      consistencyScore: consistencyScore,
      feedback: feedback,
    );
  }

  /// Evaluate the arc quality (parabolic shape)
  static double _evaluateArc(List<Offset> trajectory, Offset hoopPosition) {
    if (trajectory.length < 5) return 0.0;

    // Find the highest point in the trajectory
    double maxY = trajectory.first.dy;
    int peakIndex = 0;

    for (int i = 0; i < trajectory.length; i++) {
      if (trajectory[i].dy < maxY) {
        // invert y to account for coordinate system change on viewport
        maxY = trajectory[i].dy;
        peakIndex = i;
      }
    }

    // Good arc: peak should be roughly in the middle third of the trajectory
    final idealPeakPosition = trajectory.length / 2;
    final peakPositionError =
        (peakIndex - idealPeakPosition).abs() / trajectory.length;

    double peakPositionScore = (1 - peakPositionError * 2).clamp(0.0, 1.0);

    // Calculate arc height relative to hoop
    final startY = trajectory.first.dy;
    final arcHeight = startY - maxY;
    final verticalDistanceToHoop = (startY - hoopPosition.dy).abs();

    // Ideal arc height is 1.2x to 1.8x the vertical distance to hoop
    final arcHeightRatio = verticalDistanceToHoop > 0
        ? arcHeight / verticalDistanceToHoop
        : 0;

    double arcHeightScore;
    if (arcHeightRatio >= 1.2 && arcHeightRatio <= 1.8) {
      arcHeightScore = 1.0; // good arc height
    } else if (arcHeightRatio >= 0.8 && arcHeightRatio <= 2.2) {
      arcHeightScore = 0.7; // Acceptable
    } else {
      arcHeightScore = 0.3; // Too flat / high
    }

    // Combine scores (maximum of 30 points)
    return (peakPositionScore * 15 + arcHeightScore * 15);
  }

  /// Evaluate the release angle
  static double _evaluateReleaseAngle(List<Offset> trajectory) {
    if (trajectory.length < 3) return 0.0;

    // Calculate initial trajectory angle from first 3 points
    final p1 = trajectory[0];
    final p2 = trajectory[min(2, trajectory.length - 1)];

    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;

    // Calculate angle in degrees (negative dy = upward)
    final angleRadians = atan2(-dy, dx);
    final angleDegrees = angleRadians * 180 / pi;

    // Optimal release angle is 45-55 degrees
    // Acceptable range is 35-65 degrees
    double angleScore;
    if (angleDegrees >= 45 && angleDegrees <= 55) {
      angleScore = 1.0; // This is a good value you can use.
    } else if (angleDegrees >= 35 && angleDegrees <= 65) {
      final deviation = min(
        (angleDegrees - 45).abs(),
        (angleDegrees - 55).abs(),
      );
      angleScore = 1.0 - (deviation / 20); // Gradual falloff
    } else {
      angleScore = 0.2; // Too flat or too steep
    }

    return angleScore * 25; // Max 25 points
  }

  /// Evaluate how close the ball got to the hoop
  static double _evaluateDistanceToHoop(
    List<Offset> trajectory,
    Offset hoopPosition,
    double hoopRadius,
  ) {
    // Find closest point to hoop
    double closestDistance = double.infinity;

    for (final point in trajectory) {
      final distance = (point - hoopPosition).distance;
      if (distance < closestDistance) {
        closestDistance = distance;
      }
    }

    // DISTANCE BASED SCORING ON HOW CLOSE IT GOT TO THE HOOP
    double distanceScore;

    if (closestDistance <= hoopRadius) {
      distanceScore = 1.0; // very close
    } else if (closestDistance <= hoopRadius * 2) {
      distanceScore = 1.0 - ((closestDistance - hoopRadius) / hoopRadius) * 0.5;
    } else if (closestDistance <= hoopRadius * 3) {
      distanceScore =
          0.5 - ((closestDistance - hoopRadius * 2) / hoopRadius) * 0.4;
    } else {
      distanceScore = 0.1; // far off from hoop
    }

    return distanceScore * 25; // Max 25 points
  }

  /// Evaluate trajectory smoothness (less jitter = better)
  static double _evaluateTrajectoryConsistency(List<Offset> trajectory) {
    if (trajectory.length < 4) return 0.0;

    // Calculate direction changes
    List<double> angles = [];

    for (int i = 1; i < trajectory.length - 1; i++) {
      // CREATE THREE POINTS FOR ANGLE CALCULATION
      final p1 = trajectory[i - 1];
      final p2 = trajectory[i];
      final p3 = trajectory[i + 1];

      // CALCULATE ANGLE BETWEEN THE TWO VECTORS
      final dx1 = p2.dx - p1.dx;
      final dy1 = p2.dy - p1.dy;
      final dx2 = p3.dx - p2.dx;
      final dy2 = p3.dy - p2.dy;

      final angle1 = atan2(dy1, dx1);
      final angle2 = atan2(dy2, dx2);

      final angleChange = (angle2 - angle1).abs();
      angles.add(angleChange);
    }

    if (angles.isEmpty) return 10.0;

    // Calculate average angle change
    final avgAngleChange = angles.reduce((a, b) => a + b) / angles.length;

    // Lower angle change = smoother trajectory
    // Smooth shot: < 0.2 radians average change
    // Rough shot: > 0.5 radians average change
    double consistencyScore;
    if (avgAngleChange < 0.2) {
      consistencyScore = 1.0;
    } else if (avgAngleChange < 0.5) {
      consistencyScore = 1.0 - ((avgAngleChange - 0.2) / 0.3);
    } else {
      consistencyScore = 0.2;
    }

    return consistencyScore * 20; // Max 20 points
  }

  static String _generateFeedback({
    required double overallScore,
    required double arcScore,
    required double releaseAngleScore,
    required double distanceScore,
    required double consistencyScore,
  }) {
    List<String> feedback = [];
    if (overallScore >= 85) {
      feedback.add('Excellent shot form!');
    } else if (overallScore >= 70) {
      feedback.add('Good shot form');
    } else if (overallScore >= 50) {
      feedback.add('Decent form, room for improvement');
    } else {
      feedback.add('Needs work on technique');
    }

    // Specific feedback
    if (arcScore < 20) {
      feedback.add('Arc too flat or inconsistent');
    }
    if (releaseAngleScore < 15) {
      feedback.add('Adjust release angle (aim for 45-55°)');
    }
    if (distanceScore < 15) {
      feedback.add('Shot accuracy needs improvement');
    }
    if (consistencyScore < 12) {
      feedback.add('Work on smoother release');
    }

    return feedback.join(' • ');
  }
}

// DATA CLASS TO STORE INFORMATION
class ShotQualityResult {
  final double overallScore; // 0-100
  final double arcScore; // 0-30
  final double releaseAngleScore; // 0-25
  final double distanceScore; // 0-25
  final double consistencyScore; // 0-20
  final String feedback;

  ShotQualityResult({
    required this.overallScore,
    required this.arcScore,
    required this.releaseAngleScore,
    required this.distanceScore,
    required this.consistencyScore,
    required this.feedback,
  });
}

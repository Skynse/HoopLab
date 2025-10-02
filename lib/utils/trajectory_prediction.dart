import 'dart:math';
import 'package:flutter/material.dart';

class TrajectoryPredictor {
  /// Predict trajectory using linear regression (similar to the GitHub repo approach)
  static List<Offset> predictTrajectory({
    required List<Offset> ballPoints,
    required Offset? hoopPosition,
    int predictionSteps = 20,
  }) {
    if (ballPoints.length < 3) return [];

    // Use the last few points for prediction (more recent = more accurate)
    final recentPoints = ballPoints.length > 5
        ? ballPoints.sublist(ballPoints.length - 5)
        : ballPoints;

    if (recentPoints.length < 2) return [];

    // Perform linear regression on X and Y separately
    final xRegression = _performLinearRegression(recentPoints, true);
    final yRegression = _performLinearRegression(recentPoints, false);

    if (xRegression == null || yRegression == null) return [];

    // Generate predicted points
    List<Offset> predictedPoints = [];
    final lastTimestamp = recentPoints.length.toDouble();

    for (int i = 1; i <= predictionSteps; i++) {
      final futureTime = lastTimestamp + i;

      final predictedX = xRegression.slope * futureTime + xRegression.intercept;
      final predictedY = yRegression.slope * futureTime + yRegression.intercept;

      predictedPoints.add(Offset(predictedX, predictedY));

      // If we have a hoop position, stop prediction near the hoop
      if (hoopPosition != null) {
        final distanceToHoop = (Offset(predictedX, predictedY) - hoopPosition).distance;
        if (distanceToHoop < 50) break; // Stop within 50 pixels of hoop
      }
    }

    return predictedPoints;
  }

  /// Check if predicted trajectory intersects with hoop (shot success detection)
  /// Check if shot will go in using rim-crossing detection
  /// Uses linear interpolation between last point above rim and first point below rim
  static bool willShotGoIn({
    required List<Offset> ballPoints,
    required Offset hoopPosition,
    double hoopRadius = 30.0,
  }) {
    if (ballPoints.length < 3) return false;

    // Calculate rim height (top of hoop)
    final rimHeight = hoopPosition.dy - (hoopRadius * 0.5);

    // Find crossing points: last point above rim, first point below rim
    Offset? pointAboveRim;
    Offset? pointBelowRim;

    // Search backwards through trajectory
    for (int i = ballPoints.length - 1; i >= 0; i--) {
      if (ballPoints[i].dy < rimHeight && pointAboveRim == null) {
        pointAboveRim = ballPoints[i];
        // Get the next point (which should be below)
        if (i + 1 < ballPoints.length) {
          pointBelowRim = ballPoints[i + 1];
        }
        break;
      }
    }

    if (pointAboveRim == null || pointBelowRim == null) {
      debugPrint('❌ No rim crossing detected');
      return false;
    }

    // Linear interpolation to find X coordinate at rim height
    // Formula: x = x1 + (x2 - x1) * (rimHeight - y1) / (y2 - y1)
    final x1 = pointAboveRim.dx;
    final y1 = pointAboveRim.dy;
    final x2 = pointBelowRim.dx;
    final y2 = pointBelowRim.dy;

    final predictedX = x1 + (x2 - x1) * (rimHeight - y1) / (y2 - y1);

    // Calculate rim boundaries (use 0.8 * diameter for make detection)
    final rimLeft = hoopPosition.dx - (hoopRadius * 0.8);
    final rimRight = hoopPosition.dx + (hoopRadius * 0.8);

    final willMake = predictedX >= rimLeft && predictedX <= rimRight;

    debugPrint(
      '🏀 Rim crossing at x=${predictedX.toStringAsFixed(1)} '
      '(rim: ${rimLeft.toStringAsFixed(1)} - ${rimRight.toStringAsFixed(1)}) '
      '→ ${willMake ? "MAKE" : "MISS"}',
    );

    return willMake;
  }

  /// Calculate shot accuracy percentage based on trajectory
  static double calculateShotAccuracy({
    required List<Offset> ballPoints,
    required Offset hoopPosition,
  }) {
    if (ballPoints.isEmpty) return 0.0;

    final predictedPath = predictTrajectory(
      ballPoints: ballPoints,
      hoopPosition: hoopPosition,
    );

    if (predictedPath.isEmpty) return 0.0;

    // Find closest predicted point to hoop
    double closestDistance = double.infinity;
    for (final point in predictedPath) {
      final distance = (point - hoopPosition).distance;
      if (distance < closestDistance) {
        closestDistance = distance;
      }
    }

    // Convert distance to accuracy percentage (closer = higher accuracy)
    const maxDistance = 100.0; // pixels
    final accuracy = ((maxDistance - closestDistance) / maxDistance).clamp(0.0, 1.0);

    return accuracy * 100; // Return as percentage
  }

  /// Perform linear regression for either X or Y coordinates
  static LinearRegressionResult? _performLinearRegression(
    List<Offset> points,
    bool useX, // true for X coordinates, false for Y coordinates
  ) {
    if (points.length < 2) return null;

    double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
    final n = points.length;

    for (int i = 0; i < n; i++) {
      final x = i.toDouble(); // time index
      final y = useX ? points[i].dx : points[i].dy; // position coordinate

      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumXX += x * x;
    }

    // Calculate slope and intercept
    final denominator = n * sumXX - sumX * sumX;
    if (denominator == 0) return null; // Avoid division by zero

    final slope = (n * sumXY - sumX * sumY) / denominator;
    final intercept = (sumY - slope * sumX) / n;

    return LinearRegressionResult(slope: slope, intercept: intercept);
  }
}

class LinearRegressionResult {
  final double slope;
  final double intercept;

  LinearRegressionResult({required this.slope, required this.intercept});
}
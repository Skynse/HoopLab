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
  static bool willShotGoIn({
    required List<Offset> ballPoints,
    required Offset hoopPosition,
    double hoopRadius = 30.0, // pixels
  }) {
    final predictedPath = predictTrajectory(
      ballPoints: ballPoints,
      hoopPosition: hoopPosition,
      predictionSteps: 30,
    );

    if (predictedPath.isEmpty) return false;

    // Check if any predicted point is within hoop radius
    for (final point in predictedPath) {
      final distance = (point - hoopPosition).distance;
      if (distance <= hoopRadius) {
        debugPrint('🏀 Shot prediction: WILL GO IN (distance: ${distance.toStringAsFixed(1)}px)');
        return true;
      }
    }

    // Also check final predicted point
    final finalPoint = predictedPath.last;
    final finalDistance = (finalPoint - hoopPosition).distance;
    debugPrint('🏀 Shot prediction: WILL MISS (closest: ${finalDistance.toStringAsFixed(1)}px)');

    return false;
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
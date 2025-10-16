import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';

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
        final distanceToHoop =
            (Offset(predictedX, predictedY) - hoopPosition).distance;
        if (distanceToHoop < 50) break; // Stop within 50 pixels of hoop
      }
    }

    return predictedPoints;
  }

  /// Predict corrected arc trajectory for missed shots
  /// Returns the arc that would have made the shot go in
  static List<Offset> predictCorrectedArc({
    required List<Offset> ballPoints,
    required Offset hoopPosition,
    int predictionSteps = 30,
  }) {
    if (ballPoints.length < 3) return [];

    // Use the first few points to determine initial trajectory
    final startPoints = ballPoints.length > 5
        ? ballPoints.sublist(0, 5)
        : ballPoints;

    if (startPoints.length < 2) return [];

    // Get the starting point and initial velocity direction
    final startPoint = startPoints.first;
    final secondPoint = startPoints[1];

    // Calculate initial direction
    final initialDx = secondPoint.dx - startPoint.dx;
    final initialDy = secondPoint.dy - startPoint.dy;

    // Calculate the arc that would reach the hoop center
    final dx = hoopPosition.dx - startPoint.dx;
    final dy = hoopPosition.dy - startPoint.dy;

    List<Offset> correctedArc = [];

    // Create a parabolic arc from start to hoop
    for (int i = 0; i <= predictionSteps; i++) {
      final t = i / predictionSteps;

      // Parabolic interpolation
      // x follows linear path
      final x = startPoint.dx + dx * t;

      // y follows parabolic path with peak in the middle
      final peakHeight =
          min(startPoint.dy, hoopPosition.dy) - 100; // Arc 100px above
      final y =
          startPoint.dy +
          dy * t +
          4 * (peakHeight - startPoint.dy) * t * (1 - t);

      correctedArc.add(Offset(x, y));
    }

    return correctedArc;
  }

  /// Check if predicted trajectory intersects with hoop (shot success detection)
  /// Check if shot will go in using rim-crossing detection
  /// Uses linear interpolation between last point above rim and first point below rim
  static bool willShotGoIn({
    required List<Offset> ballPoints,
    required Offset hoopPosition,
    double hoopRadius = 30.0,
  }) {
    // add  more point in-between ballPoints if not enough
    final int originalLength = ballPoints.length;
    for (int i = 1; i < originalLength; i++) {
      Offset point1 = ballPoints[i - 1];
      Offset point2 = ballPoints[i];

      Offset inBetween = Offset.lerp(point1, point2, 0.5)!;
      Offset insertPoint = Offset.lerp(point1, inBetween, 0.5)!;
      ballPoints.insert(i, insertPoint);
    }
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

  static double calculateShotAccuracy({
    required List<Offset> ballPoints,
    required Offset hoopPosition,
    int normalizedLength = 30,
  }) {
    if (ballPoints.isEmpty) return 0.0;

    // Generate ideal trajectory
    final idealPath = predictCorrectedArc(
      ballPoints: ballPoints,
      hoopPosition: hoopPosition,
      predictionSteps: normalizedLength,
    );

    if (idealPath.isEmpty) return 0.0;

    // Normalize actual trajectory to same length
    final normalizedActual = _normalizePath(ballPoints, normalizedLength);

    // Now both paths have exactly the same number of points
    final similarity = PathSimilarity.similarityPercentage(
      normalizedActual,
      idealPath,
    );

    return similarity;
  }

  /// Helper: Resample a path to have exactly N points
  static List<Offset> _normalizePath(List<Offset> path, int targetLength) {
    if (path.isEmpty) return [];
    if (path.length == targetLength) return path;
    if (path.length == 1) return List.filled(targetLength, path[0]);

    List<Offset> normalized = [];

    for (int i = 0; i < targetLength; i++) {
      // Calculate position along the path (0.0 to 1.0)
      final t = i / (targetLength - 1);

      // Find which segment of the original path we're in
      final segmentIndex = (t * (path.length - 1)).floor();
      final segmentT = (t * (path.length - 1)) - segmentIndex;

      if (segmentIndex >= path.length - 1) {
        normalized.add(path.last);
      } else {
        // Interpolate between two points
        final point1 = path[segmentIndex];
        final point2 = path[segmentIndex + 1];
        normalized.add(Offset.lerp(point1, point2, segmentT)!);
      }
    }

    return normalized;
  }

  /// Calculate shot accuracy as percentage (0-100%)
  /// Based on how close the ball crosses the rim to the center
  /// Supports dynamic hoop tracking for moving cameras
  static ShotAccuracyResult calculateShotAccuracyFromRimCrossing({
    required List<Offset> ballPoints,
    required Offset hoopPosition,
    BoundingBox? hoopBBox,
    double hoopRadius = 30.0,
    List<FrameData>? frames, // Optional: for dynamic hoop tracking
  }) {
    // Copy list to avoid modifying original
    final points = List<Offset>.from(ballPoints);

    // Add interpolated points
    final int originalLength = points.length;
    for (int i = 1; i < originalLength; i++) {
      Offset point1 = points[i - 1];
      Offset point2 = points[i];
      Offset inBetween = Offset.lerp(point1, point2, 0.5)!;
      Offset insertPoint = Offset.lerp(point1, inBetween, 0.5)!;
      points.insert(i, insertPoint);
    }

    if (points.length < 3) {
      return ShotAccuracyResult(
        accuracy: 0.0,
        confidence: ShotConfidence.insufficient,
        reason: 'Not enough trajectory points',
      );
    }

    // Use dynamic hoop tracking if frames are provided
    Offset activeHoopPosition = hoopPosition;
    BoundingBox? activeHoopBBox = hoopBBox;

    if (frames != null && frames.isNotEmpty) {
      // Find the frame where rim crossing occurs
      // We'll update hoop position dynamically as we search
      debugPrint(
        '🎯 Using dynamic hoop tracking across ${frames.length} frames',
      );
    }

    final rimHeight = hoopBBox != null
        ? hoopBBox.y1
        : hoopPosition.dy - (hoopRadius * 0.5);

    Offset? pointAboveRim;
    Offset? pointBelowRim;
    int? crossingFrameIndex;

    for (int i = points.length - 1; i >= 0; i--) {
      // Update hoop position for this frame if using dynamic tracking
      if (frames != null && i < frames.length) {
        final frameHoop = _getHoopFromFrame(frames[i]);
        if (frameHoop != null) {
          activeHoopPosition = frameHoop;
          // Recalculate rim height for this frame's hoop position
          final frameHoopBBox = _getHoopBBoxFromFrame(frames[i]);
          if (frameHoopBBox != null) {
            activeHoopBBox = frameHoopBBox;
          }
        }
      }

      final currentRimHeight = activeHoopBBox != null
          ? activeHoopBBox.y1
          : activeHoopPosition.dy - (hoopRadius * 0.5);

      if (points[i].dy < currentRimHeight && pointAboveRim == null) {
        pointAboveRim = points[i];
        crossingFrameIndex = i;
        if (i + 1 < points.length) {
          pointBelowRim = points[i + 1];
        }
        break;
      }
    }

    if (pointAboveRim == null || pointBelowRim == null) {
      // Try fallback: use closest approach to rim if no crossing detected
      return _estimateAccuracyFromProximity(
        points: points,
        hoopPosition: hoopPosition,
        hoopBBox: hoopBBox,
        hoopRadius: hoopRadius,
      );
    }

    final x1 = pointAboveRim.dx;
    final y1 = pointAboveRim.dy;
    final x2 = pointBelowRim.dx;
    final y2 = pointBelowRim.dy;

    final predictedX = x1 + (x2 - x1) * (rimHeight - y1) / (y2 - y1);

    // Calculate accuracy based on distance from center
    // Use the active hoop position at the crossing frame
    final rimCenterX = activeHoopBBox != null
        ? activeHoopBBox.centerX
        : activeHoopPosition.dx;
    final distanceFromCenter = (predictedX - rimCenterX).abs();
    final rimWidth = activeHoopBBox != null
        ? activeHoopBBox.width
        : (hoopRadius * 2);

    if (frames != null) {
      debugPrint(
        '📍 Rim crossing at frame $crossingFrameIndex - hoop at (${activeHoopPosition.dx.toStringAsFixed(1)}, ${activeHoopPosition.dy.toStringAsFixed(1)})',
      );
    }

    // Perfect center = 100%, edge = ~0%, outside = negative (clamped to 0)
    final accuracy = ((1 - (distanceFromCenter / (rimWidth / 2))) * 100).clamp(
      0.0,
      100.0,
    );

    // Determine confidence based on trajectory completeness
    final hasFullArc = _hasCompleteArc(points, rimHeight);
    final confidence = hasFullArc ? ShotConfidence.high : ShotConfidence.medium;

    debugPrint(
      '📊 Shot Accuracy: ${accuracy.toStringAsFixed(1)}% '
      '(confidence: $confidence, distance: ${distanceFromCenter.toStringAsFixed(1)}px)',
    );

    return ShotAccuracyResult(
      accuracy: accuracy,
      confidence: confidence,
      reason: 'Rim crossing detected',
    );
  }

  /// Fallback method: estimate accuracy from closest approach to rim
  /// Used when rim crossing isn't detected (partial trajectory)
  static ShotAccuracyResult _estimateAccuracyFromProximity({
    required List<Offset> points,
    required Offset hoopPosition,
    BoundingBox? hoopBBox,
    double hoopRadius = 30.0,
  }) {
    // Find closest point to rim
    double closestDistance = double.infinity;
    Offset? closestPoint;

    for (final point in points) {
      final distance = (point - hoopPosition).distance;
      if (distance < closestDistance) {
        closestDistance = distance;
        closestPoint = point;
      }
    }

    if (closestPoint == null) {
      return ShotAccuracyResult(
        accuracy: 0.0,
        confidence: ShotConfidence.insufficient,
        reason: 'No trajectory data',
      );
    }

    final rimWidth = hoopBBox != null ? hoopBBox.width : (hoopRadius * 2);

    // If ball never got close to rim, it's clearly a miss
    if (closestDistance > rimWidth * 2) {
      return ShotAccuracyResult(
        accuracy: 0.0,
        confidence: ShotConfidence.low,
        reason:
            'Ball too far from rim (${closestDistance.toStringAsFixed(0)}px)',
      );
    }

    // Estimate accuracy based on proximity
    // Within rim width = some accuracy, farther = lower
    final accuracy = ((1 - (closestDistance / (rimWidth * 1.5))) * 100).clamp(
      0.0,
      100.0,
    );

    debugPrint(
      '⚠️ Partial trajectory - estimated accuracy: ${accuracy.toStringAsFixed(1)}% '
      '(closest: ${closestDistance.toStringAsFixed(1)}px)',
    );

    return ShotAccuracyResult(
      accuracy: accuracy,
      confidence: ShotConfidence.low,
      reason: 'Partial trajectory - estimated from proximity',
    );
  }

  /// Check if trajectory contains a complete arc (ascent + descent)
  static bool _hasCompleteArc(List<Offset> points, double rimHeight) {
    if (points.length < 5) return false;

    bool hasPointsAboveRim = points.any((p) => p.dy < rimHeight);
    bool hasPointsBelowRim = points.any((p) => p.dy > rimHeight);

    // Check for ascending phase (Y decreasing)
    bool hasAscent = false;
    for (int i = 1; i < points.length; i++) {
      if (points[i].dy < points[i - 1].dy) {
        hasAscent = true;
        break;
      }
    }

    return hasPointsAboveRim && hasPointsBelowRim && hasAscent;
  }

  /// Get hoop position from a single frame
  static Offset? _getHoopFromFrame(FrameData frame) {
    final hoopDetections = frame.detections
        .where(
          (d) =>
              d.label.toLowerCase().contains('hoop') ||
              d.label.toLowerCase().contains('rim') ||
              d.label.toLowerCase().contains('basket'),
        )
        .toList();

    if (hoopDetections.isEmpty) return null;

    final hoop = hoopDetections.first;
    return Offset(hoop.bbox.centerX, hoop.bbox.centerY);
  }

  /// Get hoop bounding box from a single frame
  static BoundingBox? _getHoopBBoxFromFrame(FrameData frame) {
    final hoopDetections = frame.detections
        .where(
          (d) =>
              d.label.toLowerCase().contains('hoop') ||
              d.label.toLowerCase().contains('rim') ||
              d.label.toLowerCase().contains('basket'),
        )
        .toList();

    if (hoopDetections.isEmpty) return null;

    return hoopDetections.first.bbox;
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

enum ShotConfidence {
  high, // Complete trajectory with rim crossing
  medium, // Partial trajectory with rim crossing
  low, // Estimated from proximity only
  insufficient, // Not enough data
}

class ShotAccuracyResult {
  final double accuracy; // 0-100%
  final ShotConfidence confidence; // How reliable is this measurement
  final String reason; // Why this confidence level

  ShotAccuracyResult({
    required this.accuracy,
    required this.confidence,
    required this.reason,
  });

  bool get isReliable =>
      confidence == ShotConfidence.high || confidence == ShotConfidence.medium;
}

class PathSimilarity {
  /// Calculate Euclidean distance between two offsets
  static double _euclideanDistance(Offset p1, Offset p2) {
    final dx = p1.dx - p2.dx;
    final dy = p1.dy - p2.dy;
    return sqrt(dx * dx + dy * dy);
  }

  /// Calculate Fréchet distance between two paths
  static double frechetDistance(List<Offset> path1, List<Offset> path2) {
    final n = path1.length;
    final m = path2.length;

    // Create memoization matrix
    final ca = List.generate(n, (_) => List.filled(m, -1.0));

    double computeCa(int i, int j) {
      if (ca[i][j] > -1) {
        return ca[i][j];
      }

      final dist = _euclideanDistance(path1[i], path2[j]);

      if (i == 0 && j == 0) {
        ca[i][j] = dist;
      } else if (i > 0 && j == 0) {
        ca[i][j] = max(computeCa(i - 1, 0), dist);
      } else if (i == 0 && j > 0) {
        ca[i][j] = max(computeCa(0, j - 1), dist);
      } else {
        ca[i][j] = max(
          min(
            min(computeCa(i - 1, j), computeCa(i - 1, j - 1)),
            computeCa(i, j - 1),
          ),
          dist,
        );
      }

      return ca[i][j];
    }

    return computeCa(n - 1, m - 1);
  }

  /// Calculate similarity percentage (0-100%)
  static double similarityPercentage(List<Offset> path1, List<Offset> path2) {
    if (path1.isEmpty || path2.isEmpty) {
      return 0.0;
    }

    final distance = frechetDistance(path1, path2);

    // Calculate max possible distance (diagonal of bounding box)
    final allPoints = [...path1, ...path2];
    final xs = allPoints.map((p) => p.dx).toList();
    final ys = allPoints.map((p) => p.dy).toList();

    final minX = xs.reduce(min);
    final maxX = xs.reduce(max);
    final minY = ys.reduce(min);
    final maxY = ys.reduce(max);

    final maxDistance = sqrt(pow(maxX - minX, 2) + pow(maxY - minY, 2));

    // Avoid division by zero
    if (maxDistance == 0) {
      return 100.0;
    }

    // Convert to similarity percentage
    final similarity = max(0.0, 100 * (1 - distance / maxDistance));
    return similarity;
  }
}

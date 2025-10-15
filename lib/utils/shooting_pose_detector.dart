import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
// Import dart:math for calculations
import 'dart:math';

/// Helper class to detect basketball shooting poses using Google ML Kit
class ShootingPoseDetector {
  final PoseDetector _poseDetector;

  // Track shooting state
  bool _isInShootingMotion = false;
  DateTime? _shootingStartTime;

  ShootingPoseDetector({PoseDetectorOptions? options})
    : _poseDetector = PoseDetector(
        options:
            options ??
            PoseDetectorOptions(
              mode: PoseDetectionMode.stream,
              model: PoseDetectionModel.accurate,
            ),
      );

  /// Detect poses in an image and return shooting motion status
  Future<ShootingPoseResult> detectShootingPose(InputImage image) async {
    try {
      final poses = await _poseDetector.processImage(image);

      debugPrint('🔍 Pose detector found ${poses.length} poses');

      if (poses.isEmpty) {
        debugPrint('⚠️ No poses detected in this frame');
        return ShootingPoseResult(
          isShootingMotion: false,
          poses: [],
          shootingConfidence: 0.0,
        );
      }

      // Analyze all detected poses for shooting motion
      double maxShootingConfidence = 0.0;
      Pose? shootingPose;

      for (final pose in poses) {
        final confidence = _analyzeShootingMotion(pose);
        if (confidence > maxShootingConfidence) {
          maxShootingConfidence = confidence;
          shootingPose = pose;
        }
      }

      // Consider it a shooting motion if confidence > 0.6
      final isCurrentlyShooting = maxShootingConfidence > 0.6;

      // Track shooting state transitions
      if (isCurrentlyShooting && !_isInShootingMotion) {
        _isInShootingMotion = true;
        _shootingStartTime = DateTime.now();
        debugPrint(
          '🏀 Shooting motion detected! Confidence: ${maxShootingConfidence.toStringAsFixed(2)}',
        );
      } else if (!isCurrentlyShooting && _isInShootingMotion) {
        _isInShootingMotion = false;
        final duration = _shootingStartTime != null
            ? DateTime.now().difference(_shootingStartTime!).inMilliseconds
            : 0;
        debugPrint('🏀 Shooting motion ended after ${duration}ms');
        _shootingStartTime = null;
      }

      return ShootingPoseResult(
        isShootingMotion: _isInShootingMotion,
        poses: poses,
        shootingConfidence: maxShootingConfidence,
        shootingPose: shootingPose,
        shootingDuration: _shootingStartTime != null
            ? DateTime.now().difference(_shootingStartTime!)
            : null,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Error detecting pose: $e');
      debugPrint('Stack trace: $stackTrace');
      return ShootingPoseResult(
        isShootingMotion: false,
        poses: [],
        shootingConfidence: 0.0,
      );
    }
  }

  /// Analyze a pose to determine if it's a basketball shooting motion
  /// Returns confidence score 0.0-1.0
  double _analyzeShootingMotion(Pose pose) {
    final landmarks = pose.landmarks;

    // Get key landmarks for shooting detection
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
    final rightElbow = landmarks[PoseLandmarkType.rightElbow];
    final rightWrist = landmarks[PoseLandmarkType.rightWrist];
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow = landmarks[PoseLandmarkType.leftElbow];
    final leftWrist = landmarks[PoseLandmarkType.leftWrist];

    // Need at least shoulder and wrist points
    if (rightShoulder == null ||
        rightWrist == null ||
        leftShoulder == null ||
        leftWrist == null) {
      return 0.0;
    }

    double confidence = 0.0;

    // Check 1: At least one arm is raised above shoulder (0.3 points)
    final rightArmRaised = rightWrist.y < rightShoulder.y;
    final leftArmRaised = leftWrist.y < leftShoulder.y;

    if (rightArmRaised || leftArmRaised) {
      confidence += 0.3;
    }

    // Check 2: Shooting arm is significantly extended upward (0.3 points)
    if (rightElbow != null) {
      final rightArmExtension = rightShoulder.y - rightWrist.y;
      if (rightArmExtension > 50) {
        // More than 50 pixels above shoulder
        confidence += 0.3;
      }
    }

    if (leftElbow != null) {
      final leftArmExtension = leftShoulder.y - leftWrist.y;
      if (leftArmExtension > 50) {
        confidence += 0.3;
      }
    }

    // Check 3: Arm angle is in shooting position (0.2 points)
    if (rightElbow != null) {
      final elbowAngle = _calculateAngle(rightShoulder, rightElbow, rightWrist);

      // Typical shooting angle is 90-160 degrees (arm extended upward)
      if (elbowAngle >= 90 && elbowAngle <= 160) {
        confidence += 0.2;
      }
    }

    if (leftElbow != null) {
      final elbowAngle = _calculateAngle(leftShoulder, leftElbow, leftWrist);

      if (elbowAngle >= 90 && elbowAngle <= 160) {
        confidence += 0.2;
      }
    }

    // Check 4: Both arms are engaged (guide hand + shooting hand) (0.2 points)
    if (rightArmRaised && leftArmRaised) {
      // Both wrists should be relatively close together (in front of face)
      final wristDistance = (rightWrist.x - leftWrist.x).abs();
      if (wristDistance < 150) {
        // Wrists within 150 pixels
        confidence += 0.2;
      }
    }

    return confidence.clamp(0.0, 1.0);
  }

  /// Calculate angle between three points (in degrees)
  double _calculateAngle(
    PoseLandmark? point1,
    PoseLandmark? point2,
    PoseLandmark? point3,
  ) {
    if (point1 == null || point2 == null || point3 == null) {
      return 0.0;
    }

    // Vector from point2 to point1
    final dx1 = point1.x - point2.x;
    final dy1 = point1.y - point2.y;

    // Vector from point2 to point3
    final dx2 = point3.x - point2.x;
    final dy2 = point3.y - point2.y;

    // Calculate angle using dot product
    final dotProduct = dx1 * dx2 + dy1 * dy2;
    final magnitude1 = sqrt(dx1 * dx1 + dy1 * dy1);
    final magnitude2 = sqrt(dx2 * dx2 + dy2 * dy2);

    if (magnitude1 == 0 || magnitude2 == 0) return 0.0;

    final cosAngle = dotProduct / (magnitude1 * magnitude2);
    final angleRadians = acos(cosAngle.clamp(-1.0, 1.0));
    final angleDegrees = angleRadians * 180 / pi;

    return angleDegrees;
  }

  /// Clean up resources
  void dispose() {
    _poseDetector.close();
  }
}

/// Result from shooting pose detection
class ShootingPoseResult {
  final bool isShootingMotion;
  final List<Pose> poses;
  final double shootingConfidence;
  final Pose? shootingPose;
  final Duration? shootingDuration;

  ShootingPoseResult({
    required this.isShootingMotion,
    required this.poses,
    required this.shootingConfidence,
    this.shootingPose,
    this.shootingDuration,
  });
}

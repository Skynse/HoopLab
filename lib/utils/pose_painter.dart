import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Paints pose skeletons (bones and joints) on the canvas
class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size imageSize;
  final Size widgetSize;

  PosePainter({
    required this.poses,
    required this.imageSize,
    required this.widgetSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final pose in poses) {
      // Draw all the bones (connections between joints)
      _drawBones(canvas, pose);

      // Draw all the joints (landmark points)
      _drawJoints(canvas, pose);
    }
  }

  void _drawBones(Canvas canvas, Pose pose) {
    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final landmarks = pose.landmarks;

    // Define bone connections (pairs of landmarks to connect)
    final connections = [
      // Face
      [PoseLandmarkType.leftEar, PoseLandmarkType.leftEye],
      [PoseLandmarkType.leftEye, PoseLandmarkType.nose],
      [PoseLandmarkType.nose, PoseLandmarkType.rightEye],
      [PoseLandmarkType.rightEye, PoseLandmarkType.rightEar],

      // Left arm
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
      [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
      [PoseLandmarkType.leftWrist, PoseLandmarkType.leftPinky],
      [PoseLandmarkType.leftWrist, PoseLandmarkType.leftIndex],
      [PoseLandmarkType.leftPinky, PoseLandmarkType.leftIndex],

      // Right arm
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
      [PoseLandmarkType.rightWrist, PoseLandmarkType.rightPinky],
      [PoseLandmarkType.rightWrist, PoseLandmarkType.rightIndex],
      [PoseLandmarkType.rightPinky, PoseLandmarkType.rightIndex],

      // Torso
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],

      // Left leg
      [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
      [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
      [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel],
      [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftFootIndex],

      // Right leg
      [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
      [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
      [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel],
      [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightFootIndex],
    ];

    for (final connection in connections) {
      final point1 = landmarks[connection[0]];
      final point2 = landmarks[connection[1]];

      if (point1 != null && point2 != null) {
        final start = _translatePoint(point1);
        final end = _translatePoint(point2);

        // Color code based on confidence
        final avgConfidence = (point1.likelihood + point2.likelihood) / 2;
        if (avgConfidence > 0.5) {
          paint.color = Colors.green;
        } else if (avgConfidence > 0.3) {
          paint.color = Colors.yellow;
        } else {
          paint.color = Colors.red.withOpacity(0.5);
        }

        canvas.drawLine(start, end, paint);
      }
    }
  }

  void _drawJoints(Canvas canvas, Pose pose) {
    final paint = Paint()..style = PaintingStyle.fill;

    final landmarks = pose.landmarks;

    for (final entry in landmarks.entries) {
      final landmark = entry.value;
      final point = _translatePoint(landmark);

      // Color based on confidence
      if (landmark.likelihood > 0.7) {
        paint.color = Colors.greenAccent;
      } else if (landmark.likelihood > 0.5) {
        paint.color = Colors.yellow;
      } else {
        paint.color = Colors.redAccent.withOpacity(0.5);
      }

      // Draw circle for joint
      canvas.drawCircle(point, 6.0, paint);

      // Draw white border
      canvas.drawCircle(
        point,
        6.0,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }
  }

  /// Translate ML Kit coordinates to widget coordinates
  Offset _translatePoint(PoseLandmark landmark) {
    // ML Kit returns coordinates in the image coordinate space
    // We need to scale them to the widget size
    final scaleX = widgetSize.width / imageSize.width;
    final scaleY = widgetSize.height / imageSize.height;

    return Offset(landmark.x * scaleX, landmark.y * scaleY);
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.poses != poses ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.widgetSize != widgetSize;
  }
}

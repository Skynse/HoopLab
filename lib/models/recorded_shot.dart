import 'package:flutter/material.dart';

/// Represents a single frame in a recorded shot
class RecordedFrame {
  final DateTime timestamp;
  final Offset? ballPosition;
  final Offset? hoopPosition;
  final double? ballSize;
  final double? hoopSize;

  RecordedFrame({
    required this.timestamp,
    this.ballPosition,
    this.hoopPosition,
    this.ballSize,
    this.hoopSize,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.millisecondsSinceEpoch,
      'ballPosition': ballPosition != null
          ? {'dx': ballPosition!.dx, 'dy': ballPosition!.dy}
          : null,
      'hoopPosition': hoopPosition != null
          ? {'dx': hoopPosition!.dx, 'dy': hoopPosition!.dy}
          : null,
      'ballSize': ballSize,
      'hoopSize': hoopSize,
    };
  }

  factory RecordedFrame.fromJson(Map<String, dynamic> json) {
    return RecordedFrame(
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
      ballPosition: json['ballPosition'] != null
          ? Offset(json['ballPosition']['dx'], json['ballPosition']['dy'])
          : null,
      hoopPosition: json['hoopPosition'] != null
          ? Offset(json['hoopPosition']['dx'], json['hoopPosition']['dy'])
          : null,
      ballSize: json['ballSize'],
      hoopSize: json['hoopSize'],
    );
  }
}

/// Represents a complete recorded shot with all frames
class RecordedShot {
  final String id;
  final DateTime recordedAt;
  final List<RecordedFrame> frames;
  final Size screenSize;
  final String? analysis;
  final double? predictedAccuracy;

  RecordedShot({
    required this.id,
    required this.recordedAt,
    required this.frames,
    required this.screenSize,
    this.analysis,
    this.predictedAccuracy,
  });

  Duration get duration {
    if (frames.isEmpty) return Duration.zero;
    return frames.last.timestamp.difference(frames.first.timestamp);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'recordedAt': recordedAt.millisecondsSinceEpoch,
      'frames': frames.map((f) => f.toJson()).toList(),
      'screenSize': {'width': screenSize.width, 'height': screenSize.height},
      'analysis': analysis,
      'predictedAccuracy': predictedAccuracy,
    };
  }

  factory RecordedShot.fromJson(Map<String, dynamic> json) {
    return RecordedShot(
      id: json['id'],
      recordedAt: DateTime.fromMillisecondsSinceEpoch(json['recordedAt']),
      frames: (json['frames'] as List)
          .map((f) => RecordedFrame.fromJson(f))
          .toList(),
      screenSize: Size(
        json['screenSize']['width'],
        json['screenSize']['height'],
      ),
      analysis: json['analysis'],
      predictedAccuracy: json['predictedAccuracy'],
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';
import 'package:video_player/video_player.dart';

class TimeLine extends StatelessWidget {
  TimeLine({
    super.key,
    required this.clip,
    required this.videoController,
    this.thumbnails,
  });

  final Clip clip;
  final VideoPlayerController videoController;
  List<File>? thumbnails;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      child: Column(
        children: [
          Text(
            'Timeline (${clip.frames.fold(0, (sum, frame) => sum + frame.detections.length)} total detections)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Stack(
                children: [
                  // Timeline background
                  Container(
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),

                  // Detection markers
                  ...clip.frames.where((frame) => frame.detections.isNotEmpty).map((
                    frame,
                  ) {
                    final videoDuration =
                        videoController.value.duration.inSeconds;
                    final position = videoDuration > 0
                        ? (frame.timestamp / videoDuration) *
                              (MediaQuery.of(context).size.width - 32 - 16)
                        : 0.0;

                    return Positioned(
                      left: position,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 3,
                        color: Colors.red,
                        child: Tooltip(
                          message:
                              '${frame.detections.length} detections at ${frame.timestamp.toStringAsFixed(1)}s',
                          child: Container(),
                        ),
                      ),
                    );
                  }),

                  Slider(
                    value: videoController.value.position.inSeconds.toDouble(),
                    max: videoController.value.duration.inSeconds.toDouble(),
                    onChanged: (value) {
                      videoController.seekTo(Duration(seconds: value.toInt()));
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

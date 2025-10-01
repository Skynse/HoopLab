import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';
import 'package:better_player_plus/better_player_plus.dart';

class TimeLine extends StatefulWidget {
  const TimeLine({
    super.key,
    required this.clip,
    required this.videoController,
    this.thumbnails,
  });

  final Clip? clip;
  final BetterPlayerController videoController;
  final List<File>? thumbnails;

  @override
  State<TimeLine> createState() => _TimeLineState();
}

class _TimeLineState extends State<TimeLine> {
  double _sliderValue = 0.0;
  bool _isUserSeeking = false;
  Timer? _seekDebounceTimer;

  @override
  void initState() {
    super.initState();
    widget.videoController.addEventsListener((event) {
      if (event.betterPlayerEventType == BetterPlayerEventType.progress) {
        _onVideoPositionChanged();
      }
    });
    _updateSliderValue();
  }

  @override
  void dispose() {
    _seekDebounceTimer?.cancel();
    // BetterPlayerController handles listeners internally
    super.dispose();
  }

  void _onVideoPositionChanged() {
    if (!_isUserSeeking && mounted) {
      _updateSliderValue();
    }
  }

  void _updateSliderValue() {
    final videoPlayerController = widget.videoController.videoPlayerController;
    if (videoPlayerController == null) return;

    try {
      // Use duration as a proxy for initialization
      if (videoPlayerController.value.duration == Duration.zero) return;

      final position = videoPlayerController.value.position.inSeconds
          .toDouble();
      final duration = videoPlayerController.value.duration!.inSeconds
          .toDouble();

      if (duration > 0 && position != _sliderValue) {
        setState(() {
          _sliderValue = position.clamp(0.0, duration);
        });
      }
    } catch (e) {
      // Silently handle initialization issues
      return;
    }
  }

  void _onSliderChanged(double value) {
    setState(() {
      _sliderValue = value;
      _isUserSeeking = true;
    });
  }

  void _onSliderChangeEnd(double value) {
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        widget.videoController
            .seekTo(Duration(seconds: value.toInt()))
            .then((_) {
              setState(() {
                _isUserSeeking = false;
              });
            })
            .catchError((error) {
              debugPrint('Seek error: $error');
              setState(() {
                _isUserSeeking = false;
              });
            });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final videoDuration = () {
      try {
        final controller = widget.videoController.videoPlayerController;
        if (controller == null || controller.value.duration == Duration.zero) {
          return 1.0;
        }
        return controller.value.duration!.inSeconds.toDouble();
      } catch (e) {
        return 1.0;
      }
    }();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Time display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatTime(_sliderValue),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              Text(
                'Detections: ${widget.clip?.frames.fold(0, (sum, frame) => sum + frame.detections.length) ?? 0}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              Text(
                _formatTime(videoDuration),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Enhanced timeline slider
          Container(
            height: 40,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                activeTrackColor: Colors.orange,
                inactiveTrackColor: Colors.grey[300],
                thumbColor: Colors.orange,
                overlayColor: Colors.orange.withOpacity(0.2),
              ),
              child: Slider(
                value: _sliderValue.clamp(0.0, videoDuration),
                min: 0.0,
                max: videoDuration,
                onChanged: _onSliderChanged,
                onChangeEnd: _onSliderChangeEnd,
              ),
            ),
          ),

          const SizedBox(height: 4),

          // Detection markers (simplified)
          if (widget.clip?.frames != null && widget.clip!.frames.isNotEmpty)
            Container(
              height: 20,
              width: double.infinity,
              child: CustomPaint(
                painter: DetectionMarkerPainter(
                  frames: widget.clip!.frames,
                  videoDuration: videoDuration,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(double seconds) {
    final duration = Duration(seconds: seconds.round());
    final minutes = duration.inMinutes;
    final remainingSeconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

class DetectionMarkerPainter extends CustomPainter {
  final List<FrameData> frames;
  final double videoDuration;

  DetectionMarkerPainter({required this.frames, required this.videoDuration});

  @override
  void paint(Canvas canvas, Size size) {
    if (videoDuration <= 0) return;

    final paint = Paint()
      ..color = Colors.orange.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    for (final frame in frames) {
      if (frame.detections.isNotEmpty) {
        final position = (frame.timestamp / videoDuration) * size.width;
        final height = (frame.detections.length / 5).clamp(0.2, 1.0) * size.height;

        canvas.drawRect(
          Rect.fromLTWH(position - 1, size.height - height, 2, height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

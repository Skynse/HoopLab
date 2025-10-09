import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';
import 'package:hooplab/widgets/clean_video_player.dart';

class TimeLine extends StatefulWidget {
  const TimeLine({
    super.key,
    required this.clip,
    required this.videoPlayerKey,
    required this.currentPosition,
    this.thumbnails,
  });

  final Clip? clip;
  final GlobalKey<CleanVideoPlayerState> videoPlayerKey;
  final Duration currentPosition;
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
    _updateSliderValue();
  }

  @override
  void didUpdateWidget(TimeLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isUserSeeking &&
        widget.currentPosition != oldWidget.currentPosition) {
      _updateSliderValue();
    }
  }

  @override
  void dispose() {
    _seekDebounceTimer?.cancel();
    super.dispose();
  }

  void _updateSliderValue() {
    final playerState = widget.videoPlayerKey.currentState;
    if (playerState == null) return;

    try {
      if (playerState.duration == Duration.zero) return;

      final position = widget.currentPosition.inSeconds.toDouble();
      final duration = playerState.duration.inSeconds.toDouble();

      if (duration > 0 && position != _sliderValue) {
        setState(() {
          _sliderValue = position.clamp(0.0, duration);
        });
      }
    } catch (e) {
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
    final playerState = widget.videoPlayerKey.currentState;
    if (playerState != null && mounted) {
      playerState
          .seekTo(Duration(seconds: value.toInt()))
          .then((_) {
            if (mounted) {
              setState(() {
                _isUserSeeking = false;
              });
            }
          })
          .catchError((error) {
            debugPrint('Seek error: $error');
            if (mounted) {
              setState(() {
                _isUserSeeking = false;
              });
            }
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoDuration = () {
      try {
        final playerState = widget.videoPlayerKey.currentState;
        if (playerState == null || playerState.duration == Duration.zero) {
          return 1.0;
        }
        return playerState.duration.inSeconds.toDouble();
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
                activeTrackColor: const Color(0xFF1565C0),
                inactiveTrackColor: Colors.grey[300],
                thumbColor: const Color(0xFF1565C0),
                overlayColor: const Color(0xFF1565C0).withOpacity(0.2),
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
      ..color = const Color(0xFF1565C0).withOpacity(0.6)
      ..style = PaintingStyle.fill;

    for (final frame in frames) {
      if (frame.detections.isNotEmpty) {
        final position = (frame.timestamp / videoDuration) * size.width;
        final height =
            (frame.detections.length / 5).clamp(0.2, 1.0) * size.height;

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

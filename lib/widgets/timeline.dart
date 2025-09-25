import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';
import 'package:video_player/video_player.dart';

class TimeLine extends StatefulWidget {
  const TimeLine({
    super.key,
    required this.clip,
    required this.videoController,
    this.thumbnails,
  });

  final Clip? clip;
  final VideoPlayerController videoController;
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
    widget.videoController.addListener(_onVideoPositionChanged);
    _updateSliderValue();
  }

  @override
  void dispose() {
    _seekDebounceTimer?.cancel();
    widget.videoController.removeListener(_onVideoPositionChanged);
    super.dispose();
  }

  void _onVideoPositionChanged() {
    if (!_isUserSeeking && mounted) {
      _updateSliderValue();
    }
  }

  void _updateSliderValue() {
    if (!widget.videoController.value.isInitialized) return;

    final position = widget.videoController.value.position.inSeconds.toDouble();
    final duration = widget.videoController.value.duration.inSeconds.toDouble();

    if (duration > 0 && position != _sliderValue) {
      setState(() {
        _sliderValue = position.clamp(0.0, duration);
      });
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
    return Container(
      height: 100,
      child: Column(
        children: [
          Text(
            'Timeline (${widget.clip?.frames.fold(0, (sum, frame) => sum + frame.detections.length)} total detections)',
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
                  if (widget.clip?.frames != null)
                    ...widget.clip!.frames
                        .where((frame) => frame.detections.isNotEmpty)
                        .map((frame) {
                          final videoDuration =
                              widget.videoController.value.duration.inSeconds;
                          final position = videoDuration > 0
                              ? (frame.timestamp / videoDuration) *
                                    (MediaQuery.of(context).size.width -
                                        32 -
                                        16)
                              : 0.0;

                          return Positioned(
                            left: position,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: 3,
                              color: Colors.red.withOpacity(0.7),
                              child: Tooltip(
                                message:
                                    '${frame.detections.length} detections at ${frame.timestamp.toStringAsFixed(1)}s',
                                child: Container(),
                              ),
                            ),
                          );
                        }),
                  // Improved slider with proper state management
                  Slider(
                    value: _sliderValue,
                    min: 0.0,
                    max: widget.videoController.value.isInitialized
                        ? widget.videoController.value.duration.inSeconds
                              .toDouble()
                        : 1.0,
                    onChanged: _onSliderChanged,
                    onChangeEnd: _onSliderChangeEnd,
                    activeColor: Colors.blue,
                    inactiveColor: Colors.grey[400],
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

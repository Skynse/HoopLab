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
                              widget
                                  .videoController
                                  .videoPlayerController
                                  ?.value
                                  .duration
                                  ?.inSeconds ??
                              0;
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
                    max: () {
                      try {
                        final controller =
                            widget.videoController.videoPlayerController;
                        if (controller == null ||
                            controller.value.duration == Duration.zero) {
                          return 1.0;
                        }
                        return controller.value.duration!.inSeconds.toDouble();
                      } catch (e) {
                        return 1.0;
                      }
                    }(),
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

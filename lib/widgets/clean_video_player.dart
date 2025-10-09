import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class CleanVideoPlayer extends StatefulWidget {
  final String videoPath;
  final Widget? overlay;
  final VoidCallback? onVideoReady;
  final Function(Duration)? onPositionChanged;

  const CleanVideoPlayer({
    super.key,
    required this.videoPath,
    this.overlay,
    this.onVideoReady,
    this.onPositionChanged,
  });

  @override
  State<CleanVideoPlayer> createState() => CleanVideoPlayerState();
}

class CleanVideoPlayerState extends State<CleanVideoPlayer> {
  late VideoPlayerController _controller;
  late ChewieController _chewieController;
  bool _isInitialized = false;
  double _aspectRatio = 16 / 9; // Default aspect ratio

  @override
  void initState() {
    super.initState();
    _initializeVideoPlayer();
  }

  void _initializeVideoPlayer() async {
    _controller = VideoPlayerController.file(File(widget.videoPath));
    await _controller.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _controller,
      autoPlay: true,
      looping: true,
      aspectRatio: _aspectRatio,
    );

    if (mounted) {
      setState(() {
        _isInitialized = true;
        // Get actual video dimensions for aspect ratio
        if (_controller.value.size != Size.zero) {
          _aspectRatio =
              _controller.value.size.width / _controller.value.size.height;
        }
      });

      widget.onVideoReady?.call();

      // Listen to position changes (throttled to avoid performance issues)
      Duration? lastReportedPosition;
      _controller.addListener(() {
        if (mounted) {
          final currentPos = _controller.value.position;
          // Only report if position changed by at least 100ms
          if (lastReportedPosition == null ||
              (currentPos - lastReportedPosition!).inMilliseconds.abs() >=
                  100) {
            lastReportedPosition = currentPos;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                widget.onPositionChanged?.call(currentPos);
              }
            });
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _chewieController.dispose();
    super.dispose();
  }

  /// Seek to specific position
  Future<void> seekTo(Duration position) async {
    if (!_isInitialized) return;

    try {
      await _chewieController.seekTo(position);
      // Force a frame update after seek
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Seek error: $e');
    }
  }

  /// Play the video
  Future<void> play() async {
    if (!_isInitialized) return;

    try {
      await _chewieController.play();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Play error: $e');
    }
  }

  /// Pause the video
  Future<void> pause() async {
    if (!_isInitialized) return;

    try {
      await _chewieController.pause();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Pause error: $e');
    }
  }

  /// Get current position
  Duration get currentPosition {
    return _controller.value.position;
  }

  /// Get video duration
  Duration get duration {
    return _controller.value.duration;
  }

  /// Get video size
  Size get videoSize {
    return _controller.value.size;
  }

  /// Check if video is playing
  bool get isPlaying {
    return _controller.value.isPlaying;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF1565C0)),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: _aspectRatio,
          child: ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, VideoPlayerValue value, child) {
              return Stack(
                children: [
                  // Video player - will rebuild when controller value changes
                  Chewie(controller: _chewieController),

                  // Custom overlay (for trajectory, etc.)
                  if (widget.overlay != null)
                    Positioned.fill(child: widget.overlay!),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

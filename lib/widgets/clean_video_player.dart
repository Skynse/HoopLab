import 'package:flutter/material.dart';
import 'package:better_player_plus/better_player_plus.dart';

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
  late BetterPlayerController _controller;
  bool _isInitialized = false;
  double _aspectRatio = 16 / 9; // Default aspect ratio

  @override
  void initState() {
    super.initState();
    _initializeVideoPlayer();
  }

  void _initializeVideoPlayer() {
    final betterPlayerConfiguration = BetterPlayerConfiguration(
      aspectRatio: null, // Let the video determine its own aspect ratio
      autoPlay: false,
      looping: false,
      fit: BoxFit.contain, // Prevent stretching
      controlsConfiguration: const BetterPlayerControlsConfiguration(
        showControls: false, // Disable built-in controls completely
        showControlsOnInitialize: false,
        enableSkips: false,
        enableFullscreen: false,
        enableMute: false,
        enablePlayPause: false,
        enableProgressBar: false,
        enableProgressBarDrag: false,
        enableProgressText: false,
      ),
    );

    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.file,
      widget.videoPath,
    );

    _controller = BetterPlayerController(betterPlayerConfiguration);
    _controller.setupDataSource(dataSource).then((_) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
          // Get actual video dimensions for aspect ratio
          final videoPlayerController = _controller.videoPlayerController;
          if (videoPlayerController != null && videoPlayerController.value.size != Size.zero) {
            _aspectRatio = videoPlayerController.value.size!.width /
                          videoPlayerController.value.size!.height;
          }
        });

        widget.onVideoReady?.call();

        // Listen to position changes
        _controller.addEventsListener((event) {
          if (event.betterPlayerEventType == BetterPlayerEventType.progress) {
            widget.onPositionChanged?.call(event.parameters?['progress'] ?? Duration.zero);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Seek to specific position
  Future<void> seekTo(Duration position) async {
    await _controller.seekTo(position);
  }

  /// Play the video
  void play() {
    _controller.play();
  }

  /// Pause the video
  void pause() {
    _controller.pause();
  }

  /// Get current position
  Duration get currentPosition {
    return _controller.videoPlayerController?.value.position ?? Duration.zero;
  }

  /// Get video duration
  Duration get duration {
    return _controller.videoPlayerController?.value.duration ?? Duration.zero;
  }

  /// Get video size
  Size get videoSize {
    return _controller.videoPlayerController?.value.size ?? const Size(1920, 1080);
  }

  /// Check if video is playing
  bool get isPlaying {
    return _controller.videoPlayerController?.value.isPlaying ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.orange),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: _aspectRatio,
          child: Stack(
            children: [
              // Video player
              BetterPlayer(controller: _controller),

              // Custom overlay (for trajectory, etc.)
              if (widget.overlay != null)
                Positioned.fill(child: widget.overlay!),
            ],
          ),
        ),
      ),
    );
  }
}
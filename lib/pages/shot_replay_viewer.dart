import 'package:flutter/material.dart';
import 'package:hooplab/models/recorded_shot.dart';
import 'dart:async';

class ShotReplayViewer extends StatefulWidget {
  final RecordedShot shot;

  const ShotReplayViewer({super.key, required this.shot});

  @override
  State<ShotReplayViewer> createState() => _ShotReplayViewerState();
}

class _ShotReplayViewerState extends State<ShotReplayViewer> {
  int _currentFrameIndex = 0;
  bool _isPlaying = false;
  Timer? _playbackTimer;
  double _playbackSpeed = 1.0;

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  void _togglePlayback() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _startPlayback();
      } else {
        _stopPlayback();
      }
    });
  }

  void _startPlayback() {
    if (widget.shot.frames.isEmpty) return;

    // Calculate frame interval
    final totalDuration = widget.shot.duration;
    final frameCount = widget.shot.frames.length;
    final msPerFrame =
        (totalDuration.inMilliseconds / frameCount) / _playbackSpeed;

    _playbackTimer = Timer.periodic(
      Duration(milliseconds: msPerFrame.round().clamp(16, 1000)),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          if (_currentFrameIndex < widget.shot.frames.length - 1) {
            _currentFrameIndex++;
          } else {
            // Loop back to start
            _currentFrameIndex = 0;
          }
        });
      },
    );
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
  }

  void _seekToFrame(int index) {
    setState(() {
      _currentFrameIndex = index.clamp(0, widget.shot.frames.length - 1);
    });
  }

  void _changeSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
      if (_isPlaying) {
        _stopPlayback();
        _startPlayback();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.shot.frames.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shot Replay')),
        body: const Center(child: Text('No frames to display')),
      );
    }

    final currentFrame = widget.shot.frames[_currentFrameIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Shot Replay'),
        actions: [
          // Speed controls
          PopupMenuButton<double>(
            icon: const Icon(Icons.speed),
            onSelected: _changeSpeed,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 0.25, child: Text('0.25x')),
              const PopupMenuItem(value: 0.5, child: Text('0.5x')),
              const PopupMenuItem(value: 1.0, child: Text('1x')),
              const PopupMenuItem(value: 2.0, child: Text('2x')),
              const PopupMenuItem(value: 4.0, child: Text('4x')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Visualization area
          Expanded(
            child: CustomPaint(
              painter: ShotTrajectoryPainter(
                frames: widget.shot.frames,
                currentFrameIndex: _currentFrameIndex,
                screenSize: widget.shot.screenSize,
              ),
              child: Container(),
            ),
          ),

          // Info panel
          Container(
            color: Colors.grey[900],
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (widget.shot.analysis != null) ...[
                  Text(
                    widget.shot.analysis!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (widget.shot.predictedAccuracy != null)
                  Text(
                    'Predicted Accuracy: ${widget.shot.predictedAccuracy!.toStringAsFixed(0)}%',
                    style: TextStyle(color: Colors.green[300], fontSize: 14),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Frame ${_currentFrameIndex + 1} / ${widget.shot.frames.length}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                // Seek bar
                Slider(
                  value: _currentFrameIndex.toDouble(),
                  min: 0,
                  max: (widget.shot.frames.length - 1).toDouble(),
                  onChanged: (value) => _seekToFrame(value.toInt()),
                ),
              ],
            ),
          ),

          // Playback controls
          Container(
            color: Colors.grey[850],
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                  onPressed: () => _seekToFrame(0),
                ),
                IconButton(
                  icon: Icon(
                    _currentFrameIndex > 0
                        ? Icons.fast_rewind
                        : Icons.fast_rewind_outlined,
                    color: Colors.white,
                  ),
                  onPressed: _currentFrameIndex > 0
                      ? () => _seekToFrame(_currentFrameIndex - 1)
                      : null,
                ),
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause_circle : Icons.play_circle,
                    color: Colors.white,
                    size: 48,
                  ),
                  onPressed: _togglePlayback,
                ),
                IconButton(
                  icon: Icon(
                    _currentFrameIndex < widget.shot.frames.length - 1
                        ? Icons.fast_forward
                        : Icons.fast_forward_outlined,
                    color: Colors.white,
                  ),
                  onPressed: _currentFrameIndex < widget.shot.frames.length - 1
                      ? () => _seekToFrame(_currentFrameIndex + 1)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                  onPressed: () => _seekToFrame(widget.shot.frames.length - 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ShotTrajectoryPainter extends CustomPainter {
  final List<RecordedFrame> frames;
  final int currentFrameIndex;
  final Size screenSize;

  ShotTrajectoryPainter({
    required this.frames,
    required this.currentFrameIndex,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate scale to fit original recording size to current canvas
    final scaleX = size.width / screenSize.width;
    final scaleY = size.height / screenSize.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final offsetX = (size.width - screenSize.width * scale) / 2;
    final offsetY = (size.height - screenSize.height * scale) / 2;

    Offset scalePoint(Offset point) {
      return Offset(point.dx * scale + offsetX, point.dy * scale + offsetY);
    }

    // Draw ball trajectory (full path up to current frame)
    final ballTrajectoryPaint = Paint()
      ..color = Colors.orange.withOpacity(0.5)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final ballTrajectoryPoints = <Offset>[];
    for (int i = 0; i <= currentFrameIndex && i < frames.length; i++) {
      if (frames[i].ballPosition != null) {
        ballTrajectoryPoints.add(scalePoint(frames[i].ballPosition!));
      }
    }

    if (ballTrajectoryPoints.length > 1) {
      final path = Path();
      path.moveTo(ballTrajectoryPoints[0].dx, ballTrajectoryPoints[0].dy);
      for (int i = 1; i < ballTrajectoryPoints.length; i++) {
        path.lineTo(ballTrajectoryPoints[i].dx, ballTrajectoryPoints[i].dy);
      }
      canvas.drawPath(path, ballTrajectoryPaint);
    }

    // Draw current ball position
    final currentFrame = frames[currentFrameIndex];
    if (currentFrame.ballPosition != null) {
      final ballPaint = Paint()
        ..color = Colors.orange
        ..style = PaintingStyle.fill;

      final ballRadius = (currentFrame.ballSize ?? 30) * scale / 2;
      canvas.drawCircle(
        scalePoint(currentFrame.ballPosition!),
        ballRadius,
        ballPaint,
      );

      // Ball outline
      final ballOutlinePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(
        scalePoint(currentFrame.ballPosition!),
        ballRadius,
        ballOutlinePaint,
      );
    }

    // Draw hoop position
    if (currentFrame.hoopPosition != null) {
      final hoopPaint = Paint()
        ..color = Colors.red.withOpacity(0.7)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke;

      final hoopRadius = (currentFrame.hoopSize ?? 60) * scale / 2;
      canvas.drawCircle(
        scalePoint(currentFrame.hoopPosition!),
        hoopRadius,
        hoopPaint,
      );

      // Draw center point
      final centerPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      canvas.drawCircle(scalePoint(currentFrame.hoopPosition!), 4, centerPaint);
    }
  }

  @override
  bool shouldRepaint(ShotTrajectoryPainter oldDelegate) {
    return oldDelegate.currentFrameIndex != currentFrameIndex ||
        oldDelegate.frames.length != frames.length;
  }
}

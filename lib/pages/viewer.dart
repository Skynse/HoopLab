import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';
import 'package:hooplab/utils/detection_painter.dart';
import 'package:hooplab/widgets/timeline.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import 'package:path/path.dart' as p;
import 'package:easy_video_editor/easy_video_editor.dart';

class ViewerPage extends StatefulWidget {
  final String? videoPath;
  ViewerPage({super.key, this.videoPath});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  bool isAnalyzing = false;
  bool isUploading = false;
  String analysisStatus = '';
  late Clip clip;
  late BetterPlayerController videoController;
  late BetterPlayerDataSource betterPlayerDataSource;
  StreamSubscription? analysisSubscription;
  YOLO? yoloModel;
  int totalFramesToProcess = 0;
  int framesProcessed = 0;
  int totalDetections = 0;
  int curFrame = 0;

  // Video info properties
  double? videoFramerate;
  int? videoDurationMs;
  int? videoWidth;
  int? videoHeight;

  // Performance optimization
  Timer? _frameUpdateTimer;
  int _lastKnownFrame = -1;
  bool _isVideoListenerActive = false;

  // Trajectory display controls
  bool _showOptimalTrajectory = true;
  bool _showBallPath = true;
  bool _calculateInFrameReference =
      false; // true = frame-of-reference, false = real-time
  @override
  void initState() {
    super.initState();
    initializeYoloModel();
    initializeVideoPlayer();
    initializeClip();

    _setupVideoListener();
  }

  void _setupVideoListener() {
    if (_isVideoListenerActive) return;
    _isVideoListenerActive = true;

    videoController.addEventsListener((event) {
      if (event.betterPlayerEventType == BetterPlayerEventType.progress) {
        _onVideoPositionChanged();
      }
    });
  }

  void _onVideoPositionChanged() {
    final videoPlayerController = videoController.videoPlayerController;
    if (!mounted || videoPlayerController == null) return;

    // Check if video player is properly initialized
    try {
      // Use duration as a proxy for initialization
      if (videoPlayerController.value.duration == Duration.zero) return;
    } catch (e) {
      return; // Fallback if initialization check fails
    }

    // Throttle UI updates to reduce jitter
    _frameUpdateTimer?.cancel();
    _frameUpdateTimer = Timer(const Duration(milliseconds: 16), () {
      if (!mounted) return;

      if (clip.frames.isNotEmpty) {
        final currentTimeSeconds =
            videoPlayerController.value.position.inMilliseconds / 1000.0;

        // Find closest frame by timestamp instead of direct calculation
        int targetFrame = _findClosestFrameIndex(currentTimeSeconds);
        targetFrame = targetFrame.clamp(0, clip.frames.length - 1);

        // Only update if frame actually changed
        if (curFrame != targetFrame && targetFrame != _lastKnownFrame) {
          curFrame = targetFrame;
          _lastKnownFrame = targetFrame;
          setState(() {});
        }
      } else {
        // Only update UI if there's an actual change
        if (_lastKnownFrame != -1) {
          _lastKnownFrame = -1;
          setState(() {});
        }
      }
    });
  }

  int _findClosestFrameIndex(double currentTimeSeconds) {
    if (clip.frames.isEmpty) return 0;

    int closestIndex = 0;
    double minDifference = double.infinity;

    for (int i = 0; i < clip.frames.length; i++) {
      final difference = (clip.frames[i].timestamp - currentTimeSeconds).abs();
      if (difference < minDifference) {
        minDifference = difference;
        closestIndex = i;
      }
    }

    return closestIndex;
  }

  Future<Map<String, dynamic>?> extractVideoFrames() async {
    try {
      debugPrint('🎬 Starting local frame extraction...');

      if (mounted) {
        setState(() {
          isUploading = true;
          analysisStatus = 'Extracting frames locally...';
        });
      }

      final videoFile = File(widget.videoPath!);
      if (!videoFile.existsSync()) {
        debugPrint('❌ Video file does not exist: ${widget.videoPath}');
        return null;
      }

      // Get video metadata first
      final editor = VideoEditorBuilder(videoPath: widget.videoPath!);
      final metadata = await editor.getVideoMetadata();

      debugPrint(
        '📊 Video metadata: ${metadata.width}x${metadata.height}, ${metadata.duration}ms, ${metadata.rotation}°',
      );

      // Calculate frame extraction parameters
      final videoDurationSeconds = metadata.duration / 1000.0;
      final targetFPS = 5.0; // Extract 5 frames per second for analysis
      final totalFramesToExtract = (videoDurationSeconds * targetFPS).ceil();
      final frameInterval = metadata.duration / totalFramesToExtract;

      debugPrint(
        '🎯 Extracting $totalFramesToExtract frames at ${targetFPS}fps interval',
      );

      // Create temporary directory for frames
      final framesDir = Directory.systemTemp.createTempSync('hooplab_frames');

      List<Map<String, dynamic>> frameData = [];

      // Extract frames at regular intervals
      for (int i = 0; i < totalFramesToExtract; i++) {
        final positionMs = (i * frameInterval).round();
        final frameName = 'frame_${i.toString().padLeft(6, '0')}.jpg';
        final framePath = p.join(framesDir.path, frameName);

        try {
          // Generate thumbnail at specific timestamp
          final thumbnailPath = await editor.generateThumbnail(
            positionMs: positionMs,
            quality: 85,
            width: metadata.width,
            height: metadata.height,
            outputPath: framePath,
          );

          if (thumbnailPath != null && File(thumbnailPath).existsSync()) {
            frameData.add({
              'frame_index': i,
              'extracted_index': i,
              'timestamp': positionMs / 1000.0,
              'filename': frameName,
              'path': thumbnailPath,
            });

            debugPrint(
              '✅ Extracted frame $i at ${(positionMs / 1000.0).toStringAsFixed(2)}s',
            );
          } else {
            debugPrint(
              '⚠️ Failed to extract frame $i at ${(positionMs / 1000.0).toStringAsFixed(2)}s',
            );
          }

          // Update progress
          if (mounted) {
            setState(() {
              analysisStatus =
                  'Extracting frames... ${i + 1}/$totalFramesToExtract';
            });
          }
        } catch (e) {
          debugPrint('❌ Error extracting frame $i: $e');
          continue;
        }
      }

      final extractedFramesCount = frameData.length;
      debugPrint('🎉 Successfully extracted $extractedFramesCount frames');

      // Build metadata response similar to server format
      final responseMetadata = {
        'fps': metadata.duration > 0
            ? (totalFramesToExtract * 1000.0) / metadata.duration
            : 30.0,
        'total_frames': totalFramesToExtract,
        'extracted_frames': extractedFramesCount,
        'frame_interval': frameInterval,
        'width': metadata.width,
        'height': metadata.height,
        'frames_directory': framesDir.path,
        'frames': frameData,
      };

      debugPrint(
        '📋 Frame extraction complete: ${extractedFramesCount} frames ready for analysis',
      );

      return responseMetadata;
    } catch (e) {
      debugPrint('❌ Error in local frame extraction: $e');
      if (mounted) {
        _showErrorDialog(
          'Frame Extraction Failed',
          'Failed to extract frames locally: $e',
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          isUploading = false;
          analysisStatus = '';
        });
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  List<Detection> getCurrentFrameDetections() {
    if (clip.frames.isEmpty || curFrame < 0 || curFrame >= clip.frames.length) {
      return [];
    }

    // Use the already calculated current frame instead of recalculating
    return clip.frames[curFrame].detections;
  }

  Timer? _seekDebounceTimer;
  // Safe video seeking with bounds checking
  Future<void> safeSeekTo(Duration position) async {
    final videoPlayerController = videoController.videoPlayerController;
    if (videoPlayerController == null) {
      debugPrint('❌ Cannot seek: video controller not available');
      return;
    }

    try {
      if (!videoPlayerController.value.initialized) {
        debugPrint('❌ Cannot seek: video not initialized');
        return;
      }
    } catch (e) {
      debugPrint('❌ Cannot seek: initialization check failed');
      return;
    }

    final duration = videoPlayerController.value.duration;
    final clampedPosition = Duration(
      milliseconds: position.inMilliseconds.clamp(0, duration!.inMilliseconds),
    );

    try {
      await videoController.seekTo(clampedPosition);
      debugPrint('✅ Seeked to ${clampedPosition.inSeconds}s');
    } catch (e) {
      debugPrint('❌ Seek error: $e');
    }
  }

  void initializeClip() {
    clip = Clip(
      id: "1",
      name: "Test Clip",
      video_path: widget.videoPath!,
      frames: [],
    );
  }

  void initializeVideoPlayer() {
    betterPlayerDataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.file,
      widget.videoPath!,
    );

    videoController = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: false,
        looping: false,
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          showControls: false,
        ),
      ),
      betterPlayerDataSource: betterPlayerDataSource,
    );

    videoController.addEventsListener((event) {
      if (event.betterPlayerEventType == BetterPlayerEventType.initialized) {
        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  void initializeYoloModel() async {
    try {
      final modelExists = await YOLO.checkModelExists('best_float16');
      print('Model exists: ${modelExists['exists']}');
      print('Location: ${modelExists['location']}');

      // 2. List available assets
      final storagePaths = await YOLO.getStoragePaths();
      print('Storage paths: $storagePaths');
      yoloModel = YOLO(modelPath: 'best_float16', task: YOLOTask.detect);
      await yoloModel!.loadModel();
      debugPrint('✅ YOLO model loaded successfully');
    } catch (e) {
      debugPrint('❌ Error initializing YOLO model: $e');
    }
  }

  @override
  void dispose() {
    _frameUpdateTimer?.cancel();
    _seekDebounceTimer?.cancel();
    analysisSubscription?.cancel();

    // BetterPlayerController handles listeners internally
    _isVideoListenerActive = false;

    videoController.dispose();
    super.dispose();
  }

  Stream<FrameData> analyzeVideoFrames() async* {
    if (yoloModel == null) {
      debugPrint('❌ YOLO model not loaded');
      return;
    }

    final videoDuration =
        videoDurationMs ??
        (videoController
                .videoPlayerController
                ?.value
                .duration!
                .inMilliseconds ??
            0);

    final Map<String, dynamic>? frameResponse = await extractVideoFrames();

    if (frameResponse == null) {
      print("FRAME RESPONSE EMPTY");
    }

    /*
         data['frame_data'].append({
                'frame_index': frame_idx,
                'extracted_index': extracted_count,
                'timestamp': timestamp,
                'frame_bytes': frame_bytes
            })

              data = {
        "fps": fps,
        "total_frames": total_frames,
        "extracted_frames": 0,
        "frame_interval": frame_interval,
        "width": width,
        "height": height,
        'frame_data': []
    }
          */

    videoWidth = frameResponse?['width'] as int?;
    videoHeight = frameResponse?['height'] as int?;
    videoFramerate = (frameResponse?['fps'] as double?);
    videoDurationMs =
        ((frameResponse?['total_frames'] as int?) ?? 0) *
        (1000 / (videoFramerate ?? 30.0)).round();

    // Calculate frame interval based on desired analysis frequency
    final analyzeEveryNthFrame = ((videoFramerate ?? 30.0) * 0.1)
        .round(); // Analyze every 0.5 seconds
    for (int idx = 0; idx < frameResponse!['extracted_frames']; idx += 1) {
      try {
        final frameNumber = idx;
        final frameInfo = frameResponse['frames'][idx];
        final preciseTimestampMs = (frameInfo['timestamp'] as double) * 1000;

        debugPrint(
          '\n🎯 Processing frame #$frameNumber at ${preciseTimestampMs}ms...',
        );

        // Use the direct path from frame info
        final framePath = frameInfo['path'] as String;
        final frameBytes = File(framePath).readAsBytesSync();
        totalFramesToProcess = frameResponse['extracted_frames'];

        final results = await yoloModel!.predict(
          frameBytes,
          confidenceThreshold: 0.7,
        );

        // Parse detections from YOLO results
        final frameDetections = <Detection>[];
        int detectionsInFrame = 0;
        var names = ["ball", "made", "person", "rim", "shoot"];

        try {
          if (results.containsKey('boxes') && results['boxes'] is List) {
            final boxes = results['boxes'] as List;
            debugPrint('📦 Found ${boxes.length} boxes in results');

            for (var box in boxes) {
              if (box is Map) {
                final x1 = (box['x1'] ?? 0).toDouble();
                final y1 = (box['y1'] ?? 0).toDouble();
                final x2 = (box['x2'] ?? 0).toDouble();
                final y2 = (box['y2'] ?? 0).toDouble();
                final confidence = (box['confidence'] ?? 0).toDouble();
                final className =
                    box['class_id']?.toString() ??
                    box['class']?.toString() ??
                    'unknown';

                if (confidence > 0.3) {
                  final detection = Detection(
                    trackId: detectionsInFrame,
                    bbox: BoundingBox(x1: x1, y1: y1, x2: x2, y2: y2),
                    confidence: confidence,
                    timestamp: preciseTimestampMs / 1000.0,
                    label: className,
                  );
                  frameDetections.add(detection);
                  detectionsInFrame++;

                  debugPrint(
                    '✅ Detection: $className (${(confidence * 100).toStringAsFixed(1)}%) at ($x1, $y1, $x2, $y2)',
                  );
                }
              }
            }
          }
        } catch (e) {
          debugPrint('❌ Error parsing results: $e');
        }

        totalDetections += detectionsInFrame;
        framesProcessed++;

        debugPrint(
          '📊 Frame #$frameNumber summary: ${detectionsInFrame} detections (Total: $totalDetections)',
        );

        final frameData = FrameData(
          frameNumber: frameNumber,
          timestamp: preciseTimestampMs / 1000.0,
          detections: frameDetections,
        );

        yield frameData;
      } catch (e) {
        debugPrint('❌ Error processing frame at ${e}ms: $e');
      }
    }

    debugPrint('\n🏁 Analysis complete:');
    debugPrint('  Frames processed: $framesProcessed');
    debugPrint('  Total detections: $totalDetections');
    debugPrint(
      '  Average detections per frame: ${totalDetections / framesProcessed.clamp(1, double.infinity)}',
    );
  }

  Widget _buildVideoPlayerWithOverlay() {
    final videoPlayerController = videoController.videoPlayerController;
    final aspectRatio = videoPlayerController?.value.aspectRatio ?? 16 / 9;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        children: [
          BetterPlayer(controller: videoController),
          // Detection overlay
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: DetectionPainter(
                        detections: getCurrentFrameDetections(),
                        videoSize: Size(
                          videoWidth?.toDouble() ?? 1080,
                          videoHeight?.toDouble() ?? 1920,
                        ),
                        widgetSize: Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                        aspectRatio: aspectRatio,
                        allFrames: clip.frames,
                        currentFrame: curFrame,
                        showTrajectories: _showBallPath,
                        showEstimatedPath: _showOptimalTrajectory,
                        calculateInFrameReference: _calculateInFrameReference,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrajectoryControlDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blue),
            child: Text(
              'Trajectory Controls',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),

          // Ball Path Toggle
          ListTile(
            leading: Icon(
              _showBallPath ? Icons.visibility : Icons.visibility_off,
              color: _showBallPath ? Colors.green : Colors.grey,
            ),
            title: const Text('Show Ball Path'),
            subtitle: const Text('Display real-time ball trajectory'),
            trailing: Switch(
              value: _showBallPath,
              onChanged: (value) {
                setState(() {
                  _showBallPath = value;
                });
              },
            ),
          ),

          const Divider(),

          // Optimal Trajectory Toggle
          ListTile(
            leading: Icon(
              _showOptimalTrajectory ? Icons.timeline : Icons.timeline_outlined,
              color: _showOptimalTrajectory ? Colors.orange : Colors.grey,
            ),
            title: const Text('Show Optimal Trajectory'),
            subtitle: const Text('Display predicted optimal shot path'),
            trailing: Switch(
              value: _showOptimalTrajectory,
              onChanged: (value) {
                setState(() {
                  _showOptimalTrajectory = value;
                });
              },
            ),
          ),

          const Divider(),

          // Calculation Mode
          ListTile(
            leading: Icon(
              _calculateInFrameReference ? Icons.camera_alt : Icons.speed,
              color: _calculateInFrameReference ? Colors.purple : Colors.blue,
            ),
            title: const Text('Calculation Mode'),
            subtitle: Text(
              _calculateInFrameReference
                  ? 'Frame-of-reference calculation'
                  : 'Real-time calculation',
            ),
            trailing: Switch(
              value: _calculateInFrameReference,
              onChanged: (value) {
                setState(() {
                  _calculateInFrameReference = value;
                });
              },
            ),
          ),

          const Divider(),

          // Info section
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Calculation Modes:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  '• Real-time: Calculations update as video plays\n'
                  '• Frame-of-reference: Calculations based on current frame position',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoPlayerController = videoController.videoPlayerController;
    if (videoPlayerController == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    try {
      if (!videoPlayerController.value.initialized) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
    } catch (e) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Video Analysis"),
          backgroundColor: Colors.blue,
          actions: [
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          ],
        ),
        endDrawer: _buildTrajectoryControlDrawer(),
        body: Stack(
          children: [
            // Main content
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Video player with detection overlay
                  Flexible(flex: 3, child: _buildVideoPlayerWithOverlay()),

                  const SizedBox(height: 20),

                  // Control buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          final videoPlayerController =
                              videoController.videoPlayerController;
                          if (videoPlayerController == null) return;

                          try {
                            if (!videoPlayerController.value.initialized)
                              return;
                          } catch (e) {
                            return;
                          }

                          try {
                            if (videoPlayerController.value.position >=
                                videoPlayerController.value.duration!) {
                              // Video has ended - seek to beginning AND play
                              await videoController.seekTo(Duration.zero);
                              await videoController.play();
                            } else {
                              // Normal play/pause toggle
                              if (videoPlayerController.value.isPlaying) {
                                await videoController.pause();
                              } else {
                                await videoController.play();
                              }
                            }
                          } catch (e) {
                            debugPrint('❌ Play/Pause error: $e');
                          }
                        },
                        icon: Icon(
                          (videoController
                                      .videoPlayerController
                                      ?.value
                                      .isPlaying ??
                                  false)
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        label: Text(
                          (videoController
                                      .videoPlayerController
                                      ?.value
                                      .isPlaying ??
                                  false)
                              ? "Pause"
                              : "Play",
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          if (isAnalyzing) {
                            analysisSubscription?.cancel();
                            setState(() {
                              isAnalyzing = false;
                            });
                          } else {
                            setState(() {
                              isAnalyzing = true;
                              clip.frames.clear();
                              totalDetections = 0;
                              framesProcessed = 0;
                            });

                            analysisSubscription = analyzeVideoFrames().listen(
                              (frameData) {
                                if (mounted) {
                                  setState(() {
                                    clip.frames.add(frameData);
                                  });
                                }
                              },

                              onDone: () {
                                if (mounted) {
                                  setState(() {
                                    isAnalyzing = false;
                                  });
                                }
                              },
                            );
                          }
                        },
                        icon: Icon(isAnalyzing ? Icons.stop : Icons.analytics),
                        label: Text(
                          isAnalyzing ? "Stop Analysis" : "Start Analysis",
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isAnalyzing
                              ? Colors.red
                              : Colors.green,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Progress and stats
                  if (isAnalyzing && totalFramesToProcess > 0) ...[
                    LinearProgressIndicator(
                      value: framesProcessed / totalFramesToProcess,
                      backgroundColor: Colors.grey[300],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Progress: $framesProcessed / $totalFramesToProcess frames',
                    ),
                    Text('Detections found: $totalDetections'),
                    const SizedBox(height: 20),
                  ],
                  TimeLine(clip: clip, videoController: videoController),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // Analysis overlay
            if (isAnalyzing || isUploading)
              Container(
                color: Colors.black.withOpacity(0.7),
                child: Center(
                  child: Card(
                    margin: const EdgeInsets.all(32.0),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            isUploading
                                ? 'Extracting Frames...'
                                : 'Analyzing Video...',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (isUploading && analysisStatus.isNotEmpty) ...[
                            Text(
                              analysisStatus,
                              style: const TextStyle(fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (!isUploading) ...[
                            Text(
                              'Processing: $framesProcessed/$totalFramesToProcess frames',
                            ),
                            Text('Detections found: $totalDetections'),
                            if (videoFramerate != null)
                              Text(
                                'Framerate: ${videoFramerate!.toStringAsFixed(1)} fps',
                              ),
                            if (totalFramesToProcess > 0) ...[
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: framesProcessed / totalFramesToProcess,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${((framesProcessed / totalFramesToProcess) * 100).toStringAsFixed(1)}% Complete',
                              ),
                            ],
                          ],
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              analysisSubscription?.cancel();
                              setState(() {
                                isAnalyzing = false;
                                isUploading = false;
                                analysisStatus = '';
                              });
                            },
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.6) return Colors.orange;
    return Colors.red;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}

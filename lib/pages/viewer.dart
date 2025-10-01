import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';
import 'package:hooplab/utils/frame_cache.dart';
import 'package:hooplab/widgets/clean_video_player.dart';
import 'package:hooplab/widgets/trajectory_overlay.dart';
import 'package:hooplab/utils/trajectory_prediction.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart';

class VideoMetadata {
  final double fps;
  final double duration;
  final int width;
  final int height;
  final int totalFrames;

  VideoMetadata({
    required this.fps,
    required this.duration,
    required this.width,
    required this.height,
    required this.totalFrames,
  });
}

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

  // Clean video player
  final GlobalKey<CleanVideoPlayerState> _videoPlayerKey = GlobalKey();
  Duration _currentVideoPosition = Duration.zero;
  StreamSubscription? analysisSubscription;
  YOLO? yoloModel;
  int totalFramesToProcess = 0;
  int framesProcessed = 0;
  int totalDetections = 0;
  int curFrame = 0;
  String? shotPrediction; // "MAKE" or "MISS"

  // Video handled by CleanVideoPlayer

  // Performance optimization
  final FrameIndexCache _frameCache = FrameIndexCache();

  // Clean display - just show ball trajectory
  @override
  void initState() {
    super.initState();
    initializeYoloModel();
    initializeVideoPlayer();
    initializeClip();
  }

  // Video listener handled by CleanVideoPlayer

  // Video position tracking handled by CleanVideoPlayer callback

  void _rebuildFrameCache() {
    if (clip.frames.isNotEmpty) {
      _frameCache.buildCache(clip.frames);
    }
  }

  Future<Map<String, dynamic>?> extractVideoFrames() async {
    try {
      debugPrint('🎬 Starting local frame extraction with video_thumbnail...');

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

      // Simple metadata estimation
      debugPrint('📊 Using simple metadata estimation...');

      final file = File(widget.videoPath!);
      final fileSize = await file.length();

      // Estimate duration based on file size (rough but reliable)
      final estimatedDuration = (fileSize / (1024 * 1024 * 2)).clamp(
        5.0,
        120.0,
      ); // 2MB per second

      final metadata = VideoMetadata(
        fps: 30.0, // Standard assumption
        duration: estimatedDuration,
        width: 1920, // HD default
        height: 1080,
        totalFrames: (30.0 * estimatedDuration).round(),
      );

      debugPrint(
        '📊 Video metadata: ${metadata.width}x${metadata.height}, ${metadata.duration}s',
      );

      // Calculate frame extraction parameters
      final videoDurationMs = (metadata.duration * 1000).round();
      final videoDurationSeconds = metadata.duration;
      final targetFPS =
          15.0; // Extract 15 frames per second for smoother analysis
      final totalFramesToExtract = (videoDurationSeconds * targetFPS).ceil();
      final frameIntervalMs = videoDurationMs / totalFramesToExtract;

      debugPrint(
        '🎯 Extracting $totalFramesToExtract frames at ${targetFPS}fps interval (${frameIntervalMs.toStringAsFixed(1)}ms apart)',
      );

      // Create temporary directory for frames
      final framesDir = Directory.systemTemp.createTempSync('hooplab_frames');

      List<Map<String, dynamic>> frameData = [];

      // Extract frames at regular intervals using video_thumbnail
      for (int i = 0; i < totalFramesToExtract; i++) {
        final positionMs = (i * frameIntervalMs).round();
        final frameName = 'frame_${i.toString().padLeft(6, '0')}.jpg';
        final framePath = p.join(framesDir.path, frameName);

        try {
          debugPrint(
            '🎬 Extracting frame $i at ${positionMs}ms (${(positionMs / 1000.0).toStringAsFixed(2)}s)',
          );

          // Generate thumbnail at specific timestamp using video_thumbnail
          final thumbnailPath = await VideoThumbnail.thumbnailFile(
            video: widget.videoPath!,
            thumbnailPath: framePath,
            imageFormat: ImageFormat.JPEG,
            timeMs: positionMs,
            quality: 85,
          );

          if (thumbnailPath != null && File(thumbnailPath).existsSync()) {
            final frameFile = File(thumbnailPath);
            final fileSize = frameFile.lengthSync();

            frameData.add({
              'frame_index': i,
              'extracted_index': i,
              'timestamp': positionMs / 1000.0,
              'filename': frameName,
              'path': thumbnailPath,
              'file_size': fileSize,
            });

            debugPrint(
              '✅ Extracted frame $i at ${(positionMs / 1000.0).toStringAsFixed(2)}s (${fileSize} bytes)',
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
        'fps': videoDurationMs > 0
            ? (totalFramesToExtract * 1000.0) / videoDurationMs
            : 30.0,
        'total_frames': totalFramesToExtract,
        'extracted_frames': extractedFramesCount,
        'frame_interval': frameIntervalMs,
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

  List<Detection> _getCurrentFrameDetections(int frameIndex) {
    if (clip.frames.isEmpty ||
        frameIndex < 0 ||
        frameIndex >= clip.frames.length) {
      return [];
    }

    return clip.frames[frameIndex].detections;
  }

  // Keep the old method for compatibility
  List<Detection> getCurrentFrameDetections() {
    return _getCurrentFrameDetections(curFrame);
  }

  void _calculateShotPrediction() {
    if (clip.frames.isEmpty) return;

    // Extract ball trajectory points
    final ballPoints = <Offset>[];
    for (final frame in clip.frames) {
      final ballDetections = frame.detections
          .where((d) => d.label.toLowerCase().contains('ball'))
          .toList();

      if (ballDetections.isNotEmpty) {
        final ball = ballDetections.first;
        ballPoints.add(Offset(ball.bbox.centerX, ball.bbox.centerY));
      }
    }

    if (ballPoints.length < 3) {
      debugPrint('⚠️ Not enough ball points for prediction');
      return;
    }

    // Find hoop position
    Offset? hoopPosition;
    for (final frame in clip.frames) {
      final hoopDetections = frame.detections
          .where(
            (d) =>
                d.label.toLowerCase().contains('hoop') ||
                d.label.toLowerCase().contains('rim') ||
                d.label.toLowerCase().contains('basket'),
          )
          .toList();

      if (hoopDetections.isNotEmpty) {
        final hoop = hoopDetections.first;
        hoopPosition = Offset(hoop.bbox.centerX, hoop.bbox.centerY);
        break;
      }
    }

    if (hoopPosition == null) {
      debugPrint('⚠️ No hoop detected in video');
      return;
    }

    // Calculate prediction
    final willMake = TrajectoryPredictor.willShotGoIn(
      ballPoints: ballPoints,
      hoopPosition: hoopPosition,
    );

    setState(() {
      shotPrediction = willMake ? "MAKE" : "MISS";
    });
  }

  Timer? _seekDebounceTimer;
  // Safe video seeking using CleanVideoPlayer
  Future<void> safeSeekTo(Duration position) async {
    final playerState = _videoPlayerKey.currentState;
    if (playerState != null) {
      try {
        await playerState.seekTo(position);
        debugPrint('✅ Seeked to ${position.inSeconds}s');
      } catch (e) {
        debugPrint('❌ Seek error: $e');
      }
    } else {
      debugPrint('❌ Cannot seek: video player not available');
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
    // Video player initialization handled by CleanVideoPlayer widget
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
    _seekDebounceTimer?.cancel();
    analysisSubscription?.cancel();
    _frameCache.clear();
    super.dispose();
  }

  Stream<FrameData> analyzeVideoFrames() async* {
    if (yoloModel == null) {
      debugPrint('❌ YOLO model not loaded');
      return;
    }

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

    // Video metadata handled by CleanVideoPlayer

    // Calculate frame interval based on desired analysis frequency
    final analyzeEveryNthFrame = (30.0 * 0.1)
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
          confidenceThreshold: 0.5,
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
    return CleanVideoPlayer(
      key: _videoPlayerKey,
      videoPath: widget.videoPath!,
      onPositionChanged: (position) {
        setState(() {
          _currentVideoPosition = position;
        });
      },
      overlay: clip.frames.isNotEmpty
          ? TrajectoryOverlay(
              frames: clip.frames,
              currentVideoPosition: _currentVideoPosition,
              videoSize:
                  _videoPlayerKey.currentState?.videoSize ??
                  const Size(1920, 1080),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Shot Analysis"),
        backgroundColor: Colors.orange,
        elevation: 0,
        actions: [],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Video player section (takes most of the screen)
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: Center(child: _buildVideoPlayerWithOverlay()),
                ),
              ),

              // Control panel
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Analysis button
                    if (!isAnalyzing && clip.frames.isEmpty)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            setState(() {
                              isAnalyzing = true;
                              clip.frames.clear();
                              totalDetections = 0;
                              framesProcessed = 0;
                              shotPrediction = null;
                            });

                            final subscription = analyzeVideoFrames().listen(
                              (frameData) {
                                if (mounted) {
                                  setState(() {
                                    clip.frames.add(frameData);
                                    _frameCache.buildCache(clip.frames);
                                    framesProcessed++;
                                    totalDetections +=
                                        frameData.detections.length;
                                  });
                                }
                              },
                              onDone: () {
                                if (mounted) {
                                  setState(() {
                                    isAnalyzing = false;
                                    _calculateShotPrediction();
                                  });
                                }
                              },
                              onError: (error) {
                                debugPrint('❌ Analysis error: $error');
                                if (mounted) {
                                  setState(() {
                                    isAnalyzing = false;
                                  });
                                }
                              },
                            );
                            analysisSubscription = subscription;
                          },
                          icon: const Icon(Icons.analytics),
                          label: const Text("Analyze Shot"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                    // Analysis in progress
                    if (isAnalyzing) ...[
                      Row(
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Analyzing frames...',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                Text(
                                  '$framesProcessed frames • $totalDetections detections',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              analysisSubscription?.cancel();
                              setState(() {
                                isAnalyzing = false;
                              });
                            },
                            child: const Text("Stop"),
                          ),
                        ],
                      ),
                    ],

                    // Analysis complete - show results
                    if (!isAnalyzing && clip.frames.isNotEmpty) ...[
                      // Shot prediction result
                      if (shotPrediction != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: shotPrediction == "MAKE"
                                ? Colors.green.withOpacity(0.1)
                                : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: shotPrediction == "MAKE"
                                  ? Colors.green
                                  : Colors.red,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                shotPrediction == "MAKE"
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                color: shotPrediction == "MAKE"
                                    ? Colors.green
                                    : Colors.red,
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                shotPrediction == "MAKE"
                                    ? "SHOT WILL GO IN"
                                    : "SHOT WILL MISS",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: shotPrediction == "MAKE"
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            clip.frames.clear();
                            totalDetections = 0;
                            framesProcessed = 0;
                            shotPrediction = null;
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text("Re-analyze"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[600],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${clip.frames.length} frames analyzed • $totalDetections detections found',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Video position and controls
                    if (clip.frames.isNotEmpty) ...[
                      Text(
                        'Video position: ${_currentVideoPosition.inSeconds}s',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),

                      // Video seek slider
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            Slider(
                              value: _currentVideoPosition.inMilliseconds
                                  .toDouble(),
                              max:
                                  (_videoPlayerKey
                                              .currentState
                                              ?.duration
                                              .inMilliseconds ??
                                          1000)
                                      .toDouble(),
                              onChanged: (value) {
                                final newPosition = Duration(
                                  milliseconds: value.round(),
                                );
                                safeSeekTo(newPosition);
                              },
                              activeColor: Colors.orange,
                              inactiveColor: Colors.grey,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${_currentVideoPosition.inSeconds}s',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  '${(_videoPlayerKey.currentState?.duration.inSeconds ?? 0)}s',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () {
                              // Skip back 1 second
                              final newPosition = Duration(
                                milliseconds:
                                    (_currentVideoPosition.inMilliseconds -
                                            1000)
                                        .clamp(0, double.infinity)
                                        .round(),
                              );
                              safeSeekTo(newPosition);
                            },
                            icon: const Icon(Icons.replay_10),
                            color: Colors.orange,
                            iconSize: 32,
                            tooltip: 'Back 1s',
                          ),
                          IconButton(
                            onPressed: () {
                              final playerState = _videoPlayerKey.currentState;
                              playerState?.pause();
                            },
                            icon: const Icon(Icons.pause),
                            color: Colors.orange,
                            iconSize: 40,
                          ),
                          IconButton(
                            onPressed: () {
                              final playerState = _videoPlayerKey.currentState;
                              playerState?.play();
                            },
                            icon: const Icon(Icons.play_arrow),
                            color: Colors.orange,
                            iconSize: 40,
                          ),
                          IconButton(
                            onPressed: () {
                              // Skip forward 1 second
                              final maxDuration =
                                  _videoPlayerKey
                                      .currentState
                                      ?.duration
                                      .inMilliseconds ??
                                  10000;
                              final newPosition = Duration(
                                milliseconds:
                                    (_currentVideoPosition.inMilliseconds +
                                            1000)
                                        .clamp(0, maxDuration.toDouble())
                                        .round(),
                              );
                              safeSeekTo(newPosition);
                            },
                            icon: const Icon(Icons.forward_10),
                            color: Colors.orange,
                            iconSize: 32,
                            tooltip: 'Forward 1s',
                          ),
                          IconButton(
                            onPressed: () {
                              safeSeekTo(Duration.zero);
                            },
                            icon: const Icon(Icons.restart_alt),
                            color: Colors.orange,
                            iconSize: 32,
                            tooltip: 'Restart',
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // Loading overlay when analyzing
          if (isAnalyzing || isUploading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Card(
                  margin: EdgeInsets.all(32),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Extracting and analyzing frames...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';
import 'package:hooplab/utils/detection_painter.dart';
import 'package:hooplab/widgets/timeline.dart';
import 'package:video_player/video_player.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import 'package:http/http.dart' as http;
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

class ViewerPage extends StatefulWidget {
  final String? videoPath;
  ViewerPage({super.key, this.videoPath});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  bool isAnalyzing = false;
  late Clip clip;
  late VideoPlayerController videoController;
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

    videoController.addListener(_onVideoPositionChanged);
  }

  void _onVideoPositionChanged() {
    if (!mounted || !videoController.value.isInitialized) return;

    // Throttle UI updates to reduce jitter
    _frameUpdateTimer?.cancel();
    _frameUpdateTimer = Timer(const Duration(milliseconds: 16), () {
      if (!mounted) return;

      if (clip.frames.isNotEmpty) {
        final currentTimeSeconds =
            videoController.value.position.inMilliseconds / 1000.0;
        final frameRate = videoFramerate ?? 30.0;

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

  Future<Map<String, dynamic>?> getVideoFrames() async {
    try {
      //var endpoint = "http://10.0.0.134:8080/extract_frames_fast/";
      var endpoint = "http://143.198.224.186:8080/extract_frames_fast/";
      var videoFile = File(widget.videoPath!);

      // Upload video file
      var request = http.MultipartRequest('POST', Uri.parse(endpoint));
      request.files.add(
        await http.MultipartFile.fromPath('file', videoFile.path),
      );
      var response = await request.send();

      if (response.statusCode != 200) {
        debugPrint('? Server error: ${response.statusCode}');
        return null;
      }

      // Save zip to a temp file
      var bytes = await response.stream.toBytes();
      var tempDir = Directory.systemTemp.createTempSync();
      var zipPath = p.join(tempDir.path, 'frames.zip');
      File(zipPath).writeAsBytesSync(bytes);

      print(zipPath);

      // Extract zip to persistent directory
      var persistentFramesDir = Directory.systemTemp.createTempSync(
        'video_frames',
      );

      print(persistentFramesDir.path);
      var archive = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
      print(archive.length.toString());
      Map<String, dynamic> metadata = {};

      for (var file in archive) {
        if (file.isFile) {
          var filename = file.name;
          var content = file.content as List<int>;

          if (filename == 'metadata.json') {
            metadata = jsonDecode(utf8.decode(content));
          } else if (filename.startsWith('frame_') &&
              filename.endsWith('.jpg')) {
            // Save frame to disk instead of memory
            var framePath = p.join(persistentFramesDir.path, filename);
            File(framePath).writeAsBytesSync(content);
          }
        }
      }

      // Add the frames directory path to metadata
      metadata['frames_directory'] = persistentFramesDir.path;

      // Clean up temp zip
      File(zipPath).deleteSync();
      tempDir.deleteSync();
      print(metadata.length);
      return metadata;
    } catch (e) {
      debugPrint('? Error fetching video frames: $e');
      return null;
    }
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
    if (!videoController.value.isInitialized) {
      debugPrint('❌ Cannot seek: video not initialized');
      return;
    }

    final duration = videoController.value.duration;
    final clampedPosition = Duration(
      milliseconds: position.inMilliseconds.clamp(0, duration.inMilliseconds),
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
    videoController = VideoPlayerController.file(File(widget.videoPath!))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
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

    // Properly remove video listener
    if (_isVideoListenerActive) {
      videoController.removeListener(_onVideoPositionChanged);
      _isVideoListenerActive = false;
    }

    videoController.dispose();
    super.dispose();
  }

  Stream<FrameData> analyzeVideoFrames() async* {
    if (yoloModel == null) {
      debugPrint('❌ YOLO model not loaded');
      return;
    }

    final videoDuration =
        videoDurationMs ?? videoController.value.duration.inMilliseconds;

    final Map<String, dynamic>? frameResponse = await getVideoFrames();

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
    double videoFramerate = (frameResponse?['fps'] as double);
    videoDurationMs =
        ((frameResponse?['total_frames'] as int?) ?? 0) *
        (1000 / (videoFramerate)).round();

    // Calculate frame interval based on desired analysis frequency
    final analyzeEveryNthFrame = (videoFramerate * 0.1)
        .round(); // Analyze every 0.5 seconds
    final frameIntervalMs = (1000 / videoFramerate * analyzeEveryNthFrame)
        .round();
    for (int idx = 0; idx < frameResponse!['extracted_frames']; idx += 1) {
      try {
        final frameNumber = idx;
        final preciseTimestampMs =
            (frameResponse['frames'][idx]['timestamp'] as double) * 1000;

        debugPrint(
          '\n🎯 Processing frame #$frameNumber at ${preciseTimestampMs}ms...',
        );

        // With this:
        final framesDir = frameResponse['frames_directory'] as String;
        final frameName = frameResponse['frames'][idx]['filename'] as String;
        final framePath = p.join(framesDir, frameName);
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
    return AspectRatio(
      aspectRatio: videoController.value.aspectRatio,
      child: Stack(
        children: [
          VideoPlayer(videoController),
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
                        aspectRatio: videoController.value.aspectRatio,
                        allFrames: clip.frames,
                        currentFrame: curFrame,
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

  @override
  Widget build(BuildContext context) {
    if (!videoController.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Video Analysis"),
          backgroundColor: Colors.blue,
        ),
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
                          if (!videoController.value.isInitialized) return;

                          try {
                            if (videoController.value.position >=
                                videoController.value.duration) {
                              // Video has ended - seek to beginning AND play
                              await videoController.seekTo(Duration.zero);
                              await videoController.play();
                            } else {
                              // Normal play/pause toggle
                              if (videoController.value.isPlaying) {
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
                          videoController.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        label: Text(
                          videoController.value.isPlaying ? "Pause" : "Play",
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
            if (isAnalyzing)
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
                          const Text(
                            'Analyzing Video...',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
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
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              analysisSubscription?.cancel();
                              setState(() {
                                isAnalyzing = false;
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

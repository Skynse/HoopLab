import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';
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
  DateTime? _lastFrameUpdate;
  @override
  void initState() {
    super.initState();
    initializeYoloModel();
    initializeVideoPlayer();
    initializeClip();

    videoController.addListener(() {
      setState(() {});
      if (videoController.value.isInitialized && clip.frames.isNotEmpty) {
        final currentTimeSeconds =
            videoController.value.position.inMilliseconds / 1000.0;
        final frameRate = videoFramerate ?? 30.0;

        // Direct frame index calculation (since you're analyzing every frame now)
        final expectedFrameIndex = (currentTimeSeconds * frameRate).round();
        final targetFrame = expectedFrameIndex.clamp(0, clip.frames.length - 1);

        if (curFrame != targetFrame) {
          curFrame = targetFrame;
          if (mounted) setState(() {});
        }
      } else {
        if (mounted) setState(() {});
      }
    });
  }

  Future<Map<String, dynamic>?> getVideoFrames() async {
    try {
      var endpoint = "http://10.0.0.134:8080/extract_frames_fast/";
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
    if (clip.frames.isEmpty) return [];

    final currentTimeSeconds =
        videoController.value.position.inMilliseconds / 1000.0;

    // Find the closest frame instead of exact match
    int closestFrame = 0;
    double minDifference = double.infinity;

    for (int i = 0; i < clip.frames.length; i++) {
      final difference = (clip.frames[i].timestamp - currentTimeSeconds).abs();
      if (difference < minDifference) {
        minDifference = difference;
        closestFrame = i;
      }
    }

    final detections = clip.frames[closestFrame].detections
        .whereType<Detection>()
        .toList();

    print(
      'Current frame at ${(currentTimeSeconds * 1000).round()}ms has ${detections.length} detections',
    );

    return detections;
  }

  Timer? _seekDebounceTimer;
  // Safe video seeking with bounds checking
  Future<void> safeSeekTo(Duration position) async {
    _seekDebounceTimer?.cancel();

    if (!videoController.value.isInitialized) {
      debugPrint('?? Video not initialized, cannot seek');
      return;
    }

    try {
      await videoController.seekTo(position);
      debugPrint('✅ Successfully sought to ${position.inMilliseconds}ms');
    } catch (e) {
      debugPrint('❌ Error seeking to ${position.inMilliseconds}ms: $e');
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
    _seekDebounceTimer?.cancel();
    analysisSubscription?.cancel();
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
          confidenceThreshold: 0.5,
        );

        print(results);

        // Parse detections from YOLO results
        final frameDetections = <Detection>[];
        int detectionsInFrame = 0;

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
                    box['className']?.toString() ??
                    box['class']?.toString() ??
                    'unknown';

                if (confidence > 0.3) {
                  final detection = Detection(
                    trackId: detectionsInFrame,
                    bbox: BoundingBox(x1: x1, y1: y1, x2: x2, y2: y2),
                    confidence: confidence,
                    timestamp: preciseTimestampMs / 1000.0,
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
                  Flexible(
                    flex: 3,
                    child: AspectRatio(
                      aspectRatio: videoController.value.aspectRatio,
                      child: Stack(
                        children: [
                          VideoPlayer(videoController),
                          // Detection overlay
                          Positioned.fill(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return IgnorePointer(
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
                                      aspectRatio:
                                          videoController.value.aspectRatio,
                                      allFrames: clip.frames,
                                      currentFrame: curFrame,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Control buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          if (videoController.value.position >=
                              videoController.value.duration) {
                            // Video has ended - seek to beginning AND play
                            await safeSeekTo(Duration.zero);
                            await videoController.play();
                          } else {
                            // Normal play/pause toggle
                            if (videoController.value.isPlaying) {
                              videoController.pause();
                            } else {
                              videoController.play();
                            }
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

                  // Video timeline with detection markers
                  if (clip.frames.isNotEmpty) ...[
                    Container(
                      height: 60,
                      child: Column(
                        children: [
                          Text(
                            'Timeline (${clip.frames.fold(0, (sum, frame) => sum + frame.detections.length)} total detections)',
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
                                  ...clip.frames
                                      .where(
                                        (frame) => frame.detections.isNotEmpty,
                                      )
                                      .map((frame) {
                                        final videoDuration = videoController
                                            .value
                                            .duration
                                            .inSeconds;
                                        final position = videoDuration > 0
                                            ? (frame.timestamp /
                                                      videoDuration) *
                                                  (MediaQuery.of(
                                                        context,
                                                      ).size.width -
                                                      32 -
                                                      16)
                                            : 0.0;

                                        return Positioned(
                                          left: position,
                                          top: 0,
                                          bottom: 0,
                                          child: Container(
                                            width: 3,
                                            color: Colors.red,
                                            child: Tooltip(
                                              message:
                                                  '${frame.detections.length} detections at ${frame.timestamp.toStringAsFixed(1)}s',
                                              child: Container(),
                                            ),
                                          ),
                                        );
                                      }),

                                  Slider(
                                    value: videoController
                                        .value
                                        .position
                                        .inSeconds
                                        .toDouble(),
                                    max: videoController
                                        .value
                                        .duration
                                        .inSeconds
                                        .toDouble(),
                                    onChanged: (value) {
                                      videoController.seekTo(
                                        Duration(seconds: value.toInt()),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
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

class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final Size videoSize;
  final Size widgetSize;
  final double aspectRatio;
  final List<FrameData> allFrames;
  final int currentFrame;
  final bool showTrajectories;

  DetectionPainter({
    required this.detections,
    required this.videoSize,
    required this.widgetSize,
    required this.aspectRatio,
    required this.allFrames,
    required this.currentFrame,
    this.showTrajectories = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (videoSize.width == 0 || videoSize.height == 0) return;

    // Calculate the actual video display area within the widget
    final widgetAspectRatio = size.width / size.height;

    final videoAspectRatio = aspectRatio;

    double videoDisplayWidth, videoDisplayHeight;
    double offsetX = 0, offsetY = 0;

    if (widgetAspectRatio > videoAspectRatio) {
      // Widget is wider than video - video will have pillarboxing (black bars on sides)
      videoDisplayHeight = size.height;
      videoDisplayWidth = videoDisplayHeight * videoAspectRatio;
      offsetX = (size.width - videoDisplayWidth) / 2;
    } else {
      // Widget is taller than video - video will have letterboxing (black bars on top/bottom)
      videoDisplayWidth = size.width;
      videoDisplayHeight = videoDisplayWidth / videoAspectRatio;
      offsetY = (size.height - videoDisplayHeight) / 2;
    }

    // Calculate scale factors from video coordinates to display coordinates
    final scaleX = videoDisplayWidth / videoSize.width;
    final scaleY = videoDisplayHeight / videoSize.height;

    // if (showTrajectories) {
    //   _drawTrajectories(canvas, scaleX, scaleY, offsetX, offsetY);
    // }

    // Draw current frame detections
    _drawCurrentDetections(canvas, size, scaleX, scaleY, offsetX, offsetY);
  }

  void _drawTrajectories(
    Canvas canvas,
    double scaleX,
    double scaleY,
    double offsetX,
    double offsetY,
  ) {
    // Group detections by track ID
    Map<int, List<Offset>> trajectories = {};

    // Collect all detection positions for each track
    for (final frame in allFrames) {
      if (frame.frameNumber > currentFrame)
        continue; // Only show past and current

      for (final detection in frame.detections) {
        final trackId = detection.trackId;
        final centerX = (detection.bbox.centerX * scaleX) + offsetX;
        final centerY = (detection.bbox.centerY * scaleY) + offsetY;

        trajectories.putIfAbsent(trackId, () => []);
        trajectories[trackId]!.add(Offset(centerX, centerY));
      }
    }

    // Draw trajectory lines for each track
    for (final entry in trajectories.entries) {
      final trackId = entry.key;
      final points = entry.value;

      if (points.length < 2) continue; // Need at least 2 points to draw a line

      final color = _getTrackColor(trackId);
      final trajectoryPaint = Paint()
        ..color = color.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      // Draw lines between consecutive points
      for (int i = 0; i < points.length - 1; i++) {
        canvas.drawLine(points[i], points[i + 1], trajectoryPaint);
      }

      // Draw small circles at each trajectory point
      final pointPaint = Paint()
        ..color = color.withOpacity(0.4)
        ..style = PaintingStyle.fill;

      for (final point in points) {
        canvas.drawCircle(point, 2, pointPaint);
      }
    }
  }

  void _drawCurrentDetections(
    Canvas canvas,
    Size size,
    double scaleX,
    double scaleY,
    double offsetX,
    double offsetY,
  ) {
    if (detections.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < detections.length; i++) {
      final detection = detections[i];

      // Get color based on track ID
      final color = _getTrackColor(detection.trackId);
      paint.color = color;

      double x1_norm = detection.bbox.x1 / videoSize.width;
      double y1_norm = detection.bbox.y1 / videoSize.height;
      double x2_norm = detection.bbox.x2 / videoSize.width;
      double y2_norm = detection.bbox.y2 / videoSize.height;

      double real_x1 = x1_norm * widgetSize.width;
      double real_y1 = y1_norm * widgetSize.height;
      double real_x2 = x2_norm * widgetSize.width;
      double real_y2 = y2_norm * widgetSize.height;

      final rect = Rect.fromLTRB(
        real_x1 + offsetX,
        real_y1 + offsetY,
        real_x2 + offsetX,
        real_y2 + offsetY,
      );

      // // Scale and offset bounding box coordinates
      // final rect = Rect.fromLTRB(
      //   (detection.bbox.x1 * scaleX) + offsetX,
      //   (detection.bbox.y1 * scaleY) + offsetY,
      //   (detection.bbox.x2 * scaleX) + offsetX,
      //   (detection.bbox.y2 * scaleY) + offsetY,
      // );

      // Draw bounding box
      canvas.drawRect(rect, paint);

      // Draw confidence and track ID
      final text =
          '🏀 ${detection.trackId} (${(detection.confidence * 100).toStringAsFixed(0)}%)';
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black87,
        ),
      );
      textPainter.layout();

      // Position text above the bounding box
      final textOffset = Offset(
        rect.left,
        (rect.top - textPainter.height - 4).clamp(
          0.0,
          size.height - textPainter.height,
        ),
      );
      textPainter.paint(canvas, textOffset);

      // Draw center point (larger and more prominent than trajectory points)
      final centerPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(rect.center, 5, centerPaint);

      // Draw white outline on center point for better visibility
      final outlinePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(rect.center, 5, outlinePaint);
    }
  }

  Color _getTrackColor(int trackId) {
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.cyan,
      Colors.pink,
      Colors.yellow,
    ];
    return colors[trackId % colors.length];
  }

  @override
  @override
  bool shouldRepaint(DetectionPainter oldDelegate) {
    // // Only repaint if current frame detections actually changed
    if (currentFrame != oldDelegate.currentFrame) {
      // Check if the detections for this specific frame are different
      final currentDetections = currentFrame < allFrames.length
          ? allFrames[currentFrame].detections
          : <Detection>[];
      final oldDetections =
          oldDelegate.currentFrame < oldDelegate.allFrames.length
          ? oldDelegate.allFrames[oldDelegate.currentFrame].detections
          : <Detection>[];

      if (currentDetections.length != oldDetections.length) return true;

      // Only repaint if detection positions/confidence actually changed
      for (int i = 0; i < currentDetections.length; i++) {
        if (i >= oldDetections.length ||
            currentDetections[i].bbox != oldDetections[i].bbox ||
            currentDetections[i].confidence != oldDetections[i].confidence) {
          return true;
        }
      }
    }

    // Always repaint for size changes
    return videoSize != oldDelegate.videoSize ||
        widgetSize != oldDelegate.widgetSize ||
        aspectRatio != oldDelegate.aspectRatio;
  }
}

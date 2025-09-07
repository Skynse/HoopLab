import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';
import 'package:video_player/video_player.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter_video_info/flutter_video_info.dart';

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

  @override
  void initState() {
    super.initState();
    initializeVideoPlayer();
    initializeYoloModel();
    initializeClip();
    getVideoInfo(); // Get video metadata including framerate

    // Listen to video position for detection overlay
    videoController.addListener(() {
      if (videoController.value.isInitialized && clip.frames.isNotEmpty) {
        final currentTimeSeconds =
            videoController.value.position.inMilliseconds / 1000.0;
        int closestFrame = 0;
        double minDifference = double.infinity;

        for (int i = 0; i < clip.frames.length; i++) {
          final difference = (clip.frames[i].timestamp - currentTimeSeconds)
              .abs();
          if (difference < minDifference) {
            minDifference = difference;
            closestFrame = i;
          }
        }

        if (mounted) {
          setState(() {
            curFrame = closestFrame;
          });
        }
      }
    });
  }

  List<Detection> getCurrentFrameDetections() {
    final frameData = clip.frames.where(
      (frame) =>
          frame.timestamp ==
          (videoController.value.position.inMilliseconds / 1000.0),
    ).firstOrNull;
    final detections =
        frameData?.detections.whereType<Detection>().toList() ?? [];
    print(
      'Current frame at ${videoController.value.position.inMilliseconds}ms has ${detections.length} detections',
    );
    if (frameData != null) {
      print(
        'Frame ${frameData.frameNumber} has ${frameData.detections.length} raw detections',
      );
    }
    return detections;
  }

  // Get video information including framerate
  Future<void> getVideoInfo() async {
    try {
      final videoInfo = FlutterVideoInfo();
      var info = await videoInfo.getVideoInfo(widget.videoPath!);

      setState(() {
        // Handle null framerate with fallback to 30 fps
        videoFramerate = info?.framerate?.toDouble() ?? 30.0;
        videoDurationMs = info?.duration?.toInt();
        videoWidth = info?.width?.toInt();
        videoHeight = info?.height?.toInt();
      });

      debugPrint('📹 Video Info:');
      debugPrint(
        '  Framerate: $videoFramerate fps ${info?.framerate == null ? "(fallback)" : "(detected)"}',
      );
      debugPrint('  Duration: $videoDurationMs ms');
      debugPrint('  Resolution: ${videoWidth}x$videoHeight');
    } catch (e) {
      debugPrint('❌ Error getting video info: $e');
      // Fallback values when the entire call fails
      videoFramerate = 30.0; // Default assumption
      videoDurationMs = videoController.value.duration.inMilliseconds;
    }
  }

  // Safe video seeking with bounds checking
  Future<void> safeSeekTo(Duration position) async {
    if (!videoController.value.isInitialized) {
      debugPrint('⚠️ Video not initialized, cannot seek');
      return;
    }

    final videoDuration = videoController.value.duration;
    if (videoDuration == Duration.zero) {
      debugPrint('⚠️ Video duration is zero, cannot seek');
      return;
    }

    // Clamp position to valid range
    Duration clampedPosition = position;
    if (position >= videoDuration) {
      clampedPosition = videoDuration - const Duration(milliseconds: 100);
      debugPrint(
        '⚠️ Seek position clamped to ${clampedPosition.inMilliseconds}ms (was ${position.inMilliseconds}ms)',
      );
    } else if (position < Duration.zero) {
      clampedPosition = Duration.zero;
      debugPrint(
        '⚠️ Seek position clamped to 0ms (was ${position.inMilliseconds}ms)',
      );
    }

    try {
      await videoController.seekTo(clampedPosition);
      debugPrint(
        '✅ Successfully sought to ${clampedPosition.inMilliseconds}ms',
      );
    } catch (e) {
      debugPrint('❌ Error seeking to ${clampedPosition.inMilliseconds}ms: $e');
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
          // Get video info after video controller is initialized
          getVideoInfo();
        }
      });
  }

  void initializeYoloModel() async {
    try {
      yoloModel = YOLO(modelPath: 'test_float16.tflite', task: YOLOTask.detect);
      await yoloModel!.loadModel();
      debugPrint('✅ YOLO model loaded successfully');
    } catch (e) {
      debugPrint('❌ Error initializing YOLO model: $e');
    }
  }

  @override
  void dispose() {
    analysisSubscription?.cancel();
    videoController.dispose();
    super.dispose();
  }

  Stream<FrameData> analyzeVideoFrames() async* {
    if (yoloModel == null) {
      debugPrint('❌ YOLO model not loaded');
      return;
    }

    // Wait for video info if not loaded yet
    while (videoFramerate == null && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final videoDuration =
        videoDurationMs ?? videoController.value.duration.inMilliseconds;
    final framerate = videoFramerate ?? 30.0; // Fallback to 30 fps

    // Calculate frame interval based on desired analysis frequency
    // For example, analyze every 30th frame (1 second at 30fps) or every 15th frame (0.5 seconds)
    final analyzeEveryNthFrame = (framerate * 0.1)
        .round(); // Analyze every 0.5 seconds
    final frameIntervalMs = (1000 / framerate * analyzeEveryNthFrame).round();

    totalFramesToProcess = (videoDuration / frameIntervalMs).ceil();
    framesProcessed = 0;
    totalDetections = 0;

    debugPrint('🎬 Starting framerate-based video analysis:');
    debugPrint('  Video framerate: ${framerate.toStringAsFixed(2)} fps');
    debugPrint('  Analyzing every ${analyzeEveryNthFrame}th frame');
    debugPrint('  Frame interval: ${frameIntervalMs}ms');
    debugPrint('  Duration: ${videoDuration}ms');
    debugPrint('  Total frames to process: $totalFramesToProcess');

    for (
      int timestampMs = 0;
      timestampMs < videoDuration;
      timestampMs += frameIntervalMs
    ) {
      try {
        // Calculate the exact frame number for more precision
        final frameNumber = (timestampMs * framerate / 1000).round();
        final preciseTimestampMs = (frameNumber * 1000 / framerate).round();

        debugPrint(
          '\n🎯 Processing frame #$frameNumber at ${preciseTimestampMs}ms...',
        );

        final extractStopwatch = Stopwatch()..start();
        final uint8list = await VideoThumbnail.thumbnailData(
          video: widget.videoPath!,
          imageFormat: ImageFormat.JPEG,
          timeMs: preciseTimestampMs,
          quality: 30,
          maxWidth: videoWidth!,
          maxHeight: videoHeight!,
        );
        extractStopwatch.stop();

        if (uint8list == null) {
          debugPrint('❌ Failed to extract frame at ${preciseTimestampMs}ms');
          continue;
        }

        debugPrint(
          '✅ Frame extracted in ${extractStopwatch.elapsedMilliseconds}ms',
        );

        final inferenceStopwatch = Stopwatch()..start();
        final results = await yoloModel!.predict(
          uint8list,
          confidenceThreshold: 0.6,
        );
        inferenceStopwatch.stop();

        debugPrint(
          '🤖 Inference completed in ${inferenceStopwatch.elapsedMilliseconds}ms',
        );

        // Parse the new format detections
        final frameDetections = <Detection>[];
        int detectionsInFrame = 0;

        try {
          if (results is Map &&
              results.containsKey('boxes') &&
              results['boxes'] is List) {
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
                    timestamp:
                        preciseTimestampMs / 1000.0, // Use precise timestamp
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
          timestamp: preciseTimestampMs / 1000.0, // Use precise timestamp
          detections: frameDetections,
        );

        yield frameData;
      } catch (e) {
        debugPrint('❌ Error processing frame at ${timestampMs}ms: $e');
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
                            child: CustomPaint(
                              painter: DetectionPainter(
                                detections: getCurrentFrameDetections(),
                                videoSize: Size(
                                  clip.videoInfo?.width.toDouble() ?? 1920,
                                  clip.videoInfo?.height.toDouble() ?? 1080,
                                ),
                                widgetSize: Size(
                                  MediaQuery.of(context).size.width - 32,
                                  (MediaQuery.of(context).size.width - 32) /
                                      videoController.value.aspectRatio,
                                ),
                                aspectRatio: videoController.value.aspectRatio,
                                allFrames: clip.frames,
                                currentFrame: curFrame,
                         
                              ),
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
                        onPressed: () {
                          if (videoController.value.position >=
                              videoController.value.duration) {
                            safeSeekTo(Duration.zero);
                          }

                          if (videoController.value.isPlaying) {
                            videoController.pause();
                          } else {
                            videoController.play();
                          }

                          setState(() {});
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
                        onPressed: videoFramerate == null
                            ? null
                            : () {
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

                                  analysisSubscription = analyzeVideoFrames()
                                      .listen(
                                        (frameData) {
                                          if (mounted) {
                                            setState(() {
                                              clip.frames.add(frameData);
                                            });
                                          }
                                        },
                                        onError: (error) {
                                          debugPrint('Analysis error: $error');
                                          if (mounted) {
                                            setState(() {
                                              isAnalyzing = false;
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
                          isAnalyzing
                              ? "Stop Analysis"
                              : videoFramerate == null
                              ? "Loading..."
                              : "Start Analysis",
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
                            child: GestureDetector(
                              onTapDown: (details) {
                                // Calculate seek position from tap location
                                final tapX = details.localPosition.dx;
                                final containerWidth =
                                    MediaQuery.of(context).size.width - 32 - 16;
                                final progress = (tapX / containerWidth).clamp(
                                  0.0,
                                  1.0,
                                );
                                final seekPosition = Duration(
                                  milliseconds:
                                      (progress *
                                              videoController
                                                  .value
                                                  .duration
                                                  .inMilliseconds)
                                          .toInt(),
                                );
                                safeSeekTo(seekPosition);
                              },
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
                                    // Detection markers
                                    ...clip.frames
                                        .where(
                                          (frame) =>
                                              frame.detections.isNotEmpty,
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
                                        })
                                        .toList(),
                                    // Current position indicator
                                    if (videoController.value.isInitialized &&
                                        videoController
                                                .value
                                                .duration
                                                .inSeconds >
                                            0)
                                      Positioned(
                                        left:
                                            (videoController
                                                    .value
                                                    .position
                                                    .inSeconds /
                                                videoController
                                                    .value
                                                    .duration
                                                    .inSeconds) *
                                            (MediaQuery.of(context).size.width -
                                                32 -
                                                16),
                                        top: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 2,
                                          color: Colors.blue,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Current frame detections list
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Frame Detections',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child:
                                clip.frames.isNotEmpty &&
                                    curFrame < clip.frames.length
                                ? ListView.builder(
                                    itemCount:
                                        clip.frames[curFrame].detections.length,
                                    itemBuilder: (context, index) {
                                      final detection = clip
                                          .frames[curFrame]
                                          .detections[index];
                                      final confidencePercent =
                                          (detection.confidence * 100).toInt();

                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.1),
                                          border: Border.all(
                                            color: Colors.green.withOpacity(
                                              0.3,
                                            ),
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.sports_basketball,
                                              color: Colors.green,
                                              size: 24,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Detection ${index + 1}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Confidence: $confidencePercent%',
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Position: (${detection.bbox.x1.toInt()}, ${detection.bbox.y1.toInt()}) to (${detection.bbox.x2.toInt()}, ${detection.bbox.y2.toInt()})',
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _getConfidenceColor(
                                                  detection.confidence,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                '$confidencePercent%',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  )
                                : const Center(
                                    child: Text(
                                      'No detections in current frame.\nRun analysis to detect objects.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
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

    // Draw trajectories first (so they appear behind current detections)
    if (showTrajectories) {
      _drawTrajectories(canvas, scaleX, scaleY, offsetX, offsetY);
    }

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

      // Scale and offset bounding box coordinates
      final rect = Rect.fromLTRB(
        (detection.bbox.x1 * scaleX) + offsetX,
        (detection.bbox.y1 * scaleY) + offsetY,
        (detection.bbox.x2 * scaleX) + offsetX,
        (detection.bbox.y2 * scaleY) + offsetY,
      );

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
  bool shouldRepaint(DetectionPainter oldDelegate) {
    return detections != oldDelegate.detections ||
        videoSize != oldDelegate.videoSize ||
        widgetSize != oldDelegate.widgetSize ||
        aspectRatio != oldDelegate.aspectRatio ||
        allFrames != oldDelegate.allFrames ||
        currentFrame != oldDelegate.currentFrame ||
        showTrajectories != oldDelegate.showTrajectories;
  }
}

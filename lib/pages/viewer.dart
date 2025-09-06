import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';
import 'package:video_player/video_player.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

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

  int curFrame = 0;
  bool seeking = false;

  @override
  void initState() {
    super.initState();
    initializeVideoPlayer();
    initializeYoloModel();
    clip = Clip(
      id: "1",
      name: "Test Clip",
      video_path: widget.videoPath!,
      frames: [],
    );

    videoController.addListener(() {
      if (!seeking && videoController.value.isInitialized) {
        setState(() {
          curFrame =
              (videoController.value.position.inMilliseconds /
                      1000.0 *
                      (clip.videoInfo?.fps ?? 30))
                  .toInt();
        });
      }
    });
  }

  void initializeVideoPlayer() {
    videoController = VideoPlayerController.file(File(widget.videoPath!))
      ..initialize().then((_) {
        setState(() {});
      });
  }

  void initializeYoloModel() async {
    try {
      yoloModel = YOLO(
        useGpu: true,
        modelPath: 'best_float16.tflite', // Remove 'assets/' prefix
        task: YOLOTask.detect,
      );

      await yoloModel!.loadModel();
      debugPrint('YOLO model loaded successfully');
    } catch (e) {
      debugPrint('Error initializing YOLO model: $e');
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
      return;
    }

    // Get video info first
    final videoDuration = videoController.value.duration.inMilliseconds;
    final videoInfo = VideoInfo(
      fps: 30, // Assuming 30 FPS; ideally, extract this from the video metadata
      totalFrames: (videoDuration / 1000 * 30)
          .toInt(), // Estimate based on 30 FPS
      duration: videoDuration / 1000.0,
      width: videoController.value.size.width.toInt(),
      height: videoController.value.size.height.toInt(),
    );

    // Update clip video info
    clip.videoInfo = videoInfo;

    // Extract and analyze frames
    final totalFrames = videoInfo.totalFrames;
    final frameInterval = 1000 ~/ videoInfo.fps; // milliseconds per frame

    for (int frameIndex = 0; frameIndex < totalFrames; frameIndex++) {
      try {
        final timestamp = frameIndex * frameInterval;

        // Extract frame using video_thumbnail
        final uint8list = await VideoThumbnail.thumbnailData(
          video: widget.videoPath!,
          imageFormat: ImageFormat.JPEG, // JPEG is faster than PNG
          timeMs: timestamp,
          quality: 75, // Reduce from 100 to 75 (still good quality)
          maxWidth: 640, // Limit max width for faster inference
          maxHeight: 640, // Limit max height for faster inference
        );

        if (uint8list != null) {
          // Run YOLO inference on the frame
          final results = await yoloModel!.predict(uint8list);

          // Convert YOLO results to our format
          final frameDetections = <Detection>[];

          // Handle the results - cast to dynamic first to avoid type inference issues
          final dynamic dynamicResults = results;

          try {
            if (dynamicResults is List) {
              for (final result in dynamicResults) {
                try {
                  // Convert each YOLO result to our Detection format
                  final detection = Detection(
                    trackId: 0, // YOLO doesn't provide tracking by default
                    bbox: BoundingBox(
                      x1: result.box?.x1?.toDouble() ?? 0.0,
                      y1: result.box?.y1?.toDouble() ?? 0.0,
                      x2: result.box?.x2?.toDouble() ?? 0.0,
                      y2: result.box?.y2?.toDouble() ?? 0.0,
                    ),
                    confidence: result.box?.conf?.toDouble() ?? 0.0,
                    timestamp: timestamp / 1000.0,
                  );
                  frameDetections.add(detection);
                } catch (e) {
                  debugPrint('Error processing YOLO result: $e');
                }
              }
            } else {
              debugPrint('YOLO results format: ${dynamicResults.runtimeType}');
              debugPrint('YOLO results content: $dynamicResults');
            }
          } catch (e) {
            debugPrint('Error processing YOLO results: $e');
          }

          final frameData = FrameData(
            frameNumber: frameIndex,
            timestamp: timestamp / 1000.0,
            detections: frameDetections,
          );

          yield frameData;
        }
      } catch (e) {
        debugPrint('Error processing frame $frameIndex: $e');
        // Continue with next frame
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!videoController.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: const Text("Viewer")),
        body: Stack(
          children: [
            // Main content
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    flex: 3,
                    child: AspectRatio(
                      aspectRatio: videoController.value.aspectRatio,
                      child: Stack(
                        children: [
                          VideoPlayer(videoController),
                          CustomPaint(
                            painter: DetectionPainter(clip.frames, curFrame),
                            size: Size.infinite,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: () {
                      if (isAnalyzing) {
                        // Stop analysis
                        analysisSubscription?.cancel();
                        setState(() {
                          isAnalyzing = false;
                        });
                      } else {
                        // Start analysis
                        setState(() {
                          isAnalyzing = true;
                          clip.frames.clear();
                        });

                        analysisSubscription = analyzeVideoFrames().listen(
                          (frameData) {
                            setState(() {
                              clip.frames.add(frameData);
                            });
                          },
                          onError: (error) {
                            debugPrint('Analysis error: $error');
                            setState(() {
                              isAnalyzing = false;
                            });
                          },
                          onDone: () {
                            debugPrint('Analysis complete');
                            setState(() {
                              isAnalyzing = false;
                            });
                          },
                        );
                      }
                    },
                    child: Text(
                      isAnalyzing ? "Stop Analysis" : "Start Analysis",
                    ),
                  ),

                  const SizedBox(height: 10),

                  clip.videoInfo != null
                      ? clip.videoInfo!.totalFrames > 0
                            ? Column(
                                children: [
                                  Slider(
                                    value: curFrame.toDouble(),
                                    min: 0,
                                    max: clip.videoInfo!.totalFrames.toDouble(),
                                    divisions: clip.videoInfo!.totalFrames,
                                    label: 'Frame $curFrame',
                                    onChangeStart: (value) {
                                      seeking = true;
                                    },
                                    onChanged: (value) {
                                      setState(() {
                                        curFrame = value.toInt();
                                      });
                                    },
                                    onChangeEnd: (value) {
                                      final position = Duration(
                                        milliseconds:
                                            (value /
                                                    (clip.videoInfo?.fps ??
                                                        30) *
                                                    1000)
                                                .toInt(),
                                      );
                                      videoController.seekTo(position);
                                      seeking = false;
                                    },
                                  ),
                                  // Detection markers overlay
                                  if (clip.frames.isNotEmpty)
                                    Container(
                                      height: 20,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                      ),
                                      child: Stack(
                                        children: clip.frames
                                            .where(
                                              (frame) =>
                                                  frame.detections.isNotEmpty,
                                            )
                                            .map((frame) {
                                              double position =
                                                  (frame.frameNumber /
                                                      clip
                                                          .videoInfo!
                                                          .totalFrames) *
                                                  (MediaQuery.of(
                                                        context,
                                                      ).size.width -
                                                      48);
                                              return Positioned(
                                                left: position,
                                                child: Container(
                                                  width: 2,
                                                  height: 20,
                                                  color: Colors.red,
                                                ),
                                              );
                                            })
                                            .toList(),
                                      ),
                                    ),
                                  Text(
                                    'Frame: $curFrame / ${clip.videoInfo?.totalFrames ?? 0}',
                                  ),
                                ],
                              )
                            : Container()
                      : Container(),

                  // Detection count display
                  if (clip.frames.isNotEmpty)
                    Text(
                      'Total detections: ${clip.frames.fold(0, (sum, frame) => sum + frame.detections.length)}',
                    ),
                ],
              ),
            ),

            // Analysis overlay
            if (isAnalyzing)
              Container(
                color: Colors.black.withValues(alpha: 0.7),
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
                          if (clip.videoInfo != null) ...[
                            Text(
                              'Processing: ${clip.frames.length}/${clip.videoInfo!.totalFrames} frames',
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value:
                                  clip.frames.length /
                                  clip.videoInfo!.totalFrames,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${((clip.frames.length / clip.videoInfo!.totalFrames) * 100).toStringAsFixed(1)}% Complete',
                            ),
                          ] else ...[
                            const Text('Initializing...'),
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
}

class DetectionPainter extends CustomPainter {
  final List<FrameData> frames;
  final int currentFrame;

  DetectionPainter(this.frames, this.currentFrame);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    // Find the frame data for the current frame
    final frameData = frames.firstWhere(
      (frame) => frame.frameNumber == currentFrame,
      orElse: () => FrameData(frameNumber: -1, timestamp: 0, detections: []),
    );

    if (frameData.frameNumber != -1) {
      for (var detection in frameData.detections) {
        final rect = Rect.fromLTRB(
          detection.bbox.x1,
          detection.bbox.y1,
          detection.bbox.x2,
          detection.bbox.y2,
        );
        canvas.drawRect(rect, paint);

        // Draw confidence score
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${(detection.confidence * 100).toInt()}%',
            style: const TextStyle(
              color: Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(detection.bbox.x1, detection.bbox.y1 - 15),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

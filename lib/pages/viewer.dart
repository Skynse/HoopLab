import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

  // For frame preview
  Uint8List? currentExtractedFrame;
  int currentTimestamp = 5000; // 5 seconds default

  @override
  void initState() {
    super.initState();
    initializeVideoPlayer();
    initializeYoloModel();
    initializeClip();
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
        setState(() {});
      });
  }

  void initializeYoloModel() async {
    try {
      yoloModel = YOLO(modelPath: 'best_float16.tflite', task: YOLOTask.detect);
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

  Future<void> extractAndShowFrame() async {
    try {
      debugPrint('🖼️ Extracting frame at ${currentTimestamp}ms...');

      final extractStopwatch = Stopwatch()..start();
      final uint8list = await VideoThumbnail.thumbnailData(
        video: widget.videoPath!,
        imageFormat: ImageFormat.JPEG,
        timeMs: currentTimestamp,
        quality: 75,
        maxWidth: 640,
        maxHeight: 640,
      );
      extractStopwatch.stop();

      if (uint8list == null) {
        debugPrint('❌ Failed to extract frame');
        return;
      }

      debugPrint(
        '✅ Frame extracted in ${extractStopwatch.elapsedMilliseconds}ms',
      );
      debugPrint('   Frame size: ${uint8list.length} bytes');

      setState(() {
        currentExtractedFrame = uint8list;
      });

      // Test YOLO prediction on this frame
      if (yoloModel != null) {
        debugPrint('🤖 Running YOLO on extracted frame...');
        final inferenceStopwatch = Stopwatch()..start();
        final results = await yoloModel!.predict(uint8list, iouThreshold: 0.1);
        print(results);
        inferenceStopwatch.stop();

        debugPrint(
          '🤖 Inference completed in ${inferenceStopwatch.elapsedMilliseconds}ms',
        );
        debugPrint('📊 Raw results: $results');

        // Try to count detections
        int detectionCount = 0;
        if (results is Map) {
          if (results.containsKey('boxes') && results['boxes'] is List) {
            detectionCount = (results['boxes'] as List).length;
          }
        } else if (results is List) {
          detectionCount = results.length;
        }

        debugPrint('🎯 Found $detectionCount detections');
      }
    } catch (e) {
      debugPrint('❌ Error extracting frame: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!videoController.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Frame Extraction Debug"),
          backgroundColor: Colors.blue,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Original video
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    const Text(
                      'Original Video',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: videoController.value.aspectRatio,
                        child: VideoPlayer(videoController),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Timestamp selector
              Row(
                children: [
                  const Text('Timestamp: '),
                  Expanded(
                    child: Slider(
                      value: currentTimestamp.toDouble(),
                      min: 0,
                      max: videoController.value.duration.inMilliseconds
                          .toDouble(),
                      divisions: 20,
                      label: '${(currentTimestamp / 1000).toStringAsFixed(1)}s',
                      onChanged: (value) {
                        setState(() {
                          currentTimestamp = value.toInt();
                        });
                      },
                    ),
                  ),
                  Text('${(currentTimestamp / 1000).toStringAsFixed(1)}s'),
                ],
              ),

              const SizedBox(height: 10),

              // Extract frame button
              ElevatedButton(
                onPressed: extractAndShowFrame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text(
                  'Extract & Analyze Frame',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),

              const SizedBox(height: 20),

              // Extracted frame preview
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    const Text(
                      'Extracted Frame (What YOLO Sees)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: currentExtractedFrame != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  currentExtractedFrame!,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : const Center(
                                child: Text(
                                  'Click "Extract & Analyze Frame" to see what YOLO receives',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Seek video to same timestamp button
              ElevatedButton(
                onPressed: () {
                  videoController.seekTo(
                    Duration(milliseconds: currentTimestamp),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 40),
                ),
                child: const Text(
                  'Seek Video to Same Time',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

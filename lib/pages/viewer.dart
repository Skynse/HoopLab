import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';
import 'package:video_player/video_player.dart';

class ViewerPage extends StatefulWidget {
  String? videoPath;
  ViewerPage({super.key, this.videoPath});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  bool isAnalyzing = false;
  late Clip clip;
  late VideoPlayerController videoController;
  Timer? frameTimer;

  void initializeVideoPlayer() {
    videoController = VideoPlayerController.file(File(widget.videoPath!))
      ..initialize().then((_) {
        setState(() {});
      });
  }

  @override
  void initState() {
    initializeVideoPlayer();
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void AnalyzeFrames() async {
    videoController.play();
  }

  @override
  Widget build(BuildContext context) {
    if (!videoController.value.isInitialized) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return SafeArea(child: Scaffold(
      appBar: AppBar(title: Text("Viewer")),
      body: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
        Flexible(
          flex: 3,
          child: AspectRatio(
          aspectRatio: videoController.value.aspectRatio,
          child: VideoPlayer(videoController),
          ),
        ),
        SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
          if (isAnalyzing) {
            videoController.pause();
            setState(() {
            isAnalyzing = false;
            });
          } else {
            AnalyzeFrames();
            setState(() {
            isAnalyzing = true;
            });
          }
          },
          child: Text(isAnalyzing ? "Stop Analysis" : "Start Analysis"),
        ),
        ],
      ),
      ),
    ),
    );
  }
}

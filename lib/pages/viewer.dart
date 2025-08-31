import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooplab/models/clip.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;

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

  Stream<Map<String, dynamic>>? fetchData() {
    // var endpoint = Uri.parse('127.0.0.1:8000/analyze');
    var endpoint = Uri.parse('172.20.20.20:8000/analyze');
    File videoFile = File(widget.videoPath!);
    var request = http.MultipartRequest('POST', endpoint);
    request.files.add(
      http.MultipartFile(
        'video',
        videoFile.readAsBytes().asStream(),
        videoFile.lengthSync(),
        filename: videoFile.path.split("/").last,
      ),
    );
    var response = request.send();
    return response.asStream().asyncExpand((response) {
      return response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) => json.decode(line) as Map<String, dynamic>);
    });
  }

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
    return SafeArea(
      child: Scaffold(
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
                  setState(() {
                    isAnalyzing = !isAnalyzing;
                    if (isAnalyzing) {
                      fetchData()?.listen((data) {
                        print(data);
                      });
                    }
                  });
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

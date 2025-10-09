import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:ultralytics_yolo/models/yolo_result.dart';

class LiveShotDetector extends StatefulWidget {
  const LiveShotDetector({super.key});

  @override
  State<LiveShotDetector> createState() => _LiveShotDetectorState();
}

class _LiveShotDetectorState extends State<LiveShotDetector> {
  List<YOLOResult> _detections = [];
  bool _isBallDetected = false;
  bool _isHoopDetected = false;
  int _frameCount = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Shot Detection'),
        actions: [
          // Status indicators
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(
                  Icons.sports_basketball,
                  color: _isBallDetected ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.sports_score,
                  color: _isHoopDetected ? Colors.green : Colors.grey,
                  size: 20,
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // YOLO real-time detection view
          YOLOView(
            modelPath: 'assets/best_float16.tflite',
            task: YOLOTask.detect,
            confidenceThreshold: 0.3,
            iouThreshold: 0.4,
            onResult: _handleDetectionResults,
          ),

          // Overlay with detection info
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Detection stats
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatCard(
                        'Ball',
                        _isBallDetected ? 'Detected' : 'Not Found',
                        _isBallDetected ? Colors.green : Colors.red,
                      ),
                      _buildStatCard(
                        'Hoop',
                        _isHoopDetected ? 'Detected' : 'Not Found',
                        _isHoopDetected ? Colors.green : Colors.red,
                      ),
                      _buildStatCard(
                        'Objects',
                        '${_detections.length}',
                        Colors.blue,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Instructions
                  Text(
                    _getInstructions(),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          // Crosshair for aiming
          Center(
            child: Icon(
              Icons.my_location,
              color: Colors.white.withOpacity(0.3),
              size: 48,
            ),
          ),
        ],
      ),
    );
  }

  void _handleDetectionResults(List<YOLOResult> results) {
    if (!mounted) return;

    setState(() {
      _detections = results;
      _frameCount++;

      // Check for ball and hoop
      _isBallDetected = results.any(
        (r) => r.className.toLowerCase().contains('ball'),
      );
      _isHoopDetected = results.any(
        (r) =>
            r.className.toLowerCase().contains('hoop') ||
            r.className.toLowerCase().contains('rim') ||
            r.className.toLowerCase().contains('basket'),
      );
    });
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _getInstructions() {
    if (!_isBallDetected && !_isHoopDetected) {
      return '🎯 Point camera at basketball hoop and ball';
    } else if (!_isBallDetected) {
      return '🏀 Ball not detected - make sure it\'s visible';
    } else if (!_isHoopDetected) {
      return '🎯 Hoop not detected - keep it in frame';
    } else {
      return '✅ Ready! Take your shot and watch the trajectory';
    }
  }
}

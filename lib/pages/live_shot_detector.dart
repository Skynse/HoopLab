import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:hooplab/models/recorded_shot.dart';
import 'package:hooplab/pages/shot_replay_viewer.dart';

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

  // Track ball trajectory for live shot analysis
  final List<Offset> _ballTrajectory = [];
  final List<DateTime> _trajectoryTimestamps = [];
  Offset? _currentBallPosition;
  Offset? _currentHoopPosition;
  double? _currentBallSize;
  double? _currentHoopSize;

  // Shot state
  bool _shotInProgress = false;
  String _liveAnalysis = '';
  double? _predictedAccuracy;

  // Recording state
  bool _isRecording = false;
  List<RecordedFrame> _recordedFrames = [];
  DateTime? _recordingStartTime;
  final List<RecordedShot> _recordedShots = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Shot Detection'),
        actions: [
          // View recorded shots
          if (_recordedShots.isNotEmpty)
            IconButton(
              icon: Badge(
                label: Text('${_recordedShots.length}'),
                child: const Icon(Icons.video_library),
              ),
              onPressed: _showRecordedShotsList,
              tooltip: 'View recorded shots',
            ),
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
            modelPath: 'best_float16',
            task: YOLOTask.detect,
            confidenceThreshold: 0.5,
            iouThreshold: 0.4,
            onResult: (x) => throw (),
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
                  // Live shot analysis or instructions
                  if (_shotInProgress && _liveAnalysis.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'LIVE SHOT ANALYSIS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _liveAnalysis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_predictedAccuracy != null)
                            Text(
                              'Predicted: ${_predictedAccuracy!.toStringAsFixed(0)}%',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ] else
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

          // Recording button
          Positioned(
            bottom: 180,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _toggleRecording,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? Colors.red : Colors.white,
                    border: Border.all(
                      color: _isRecording ? Colors.white : Colors.red,
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.fiber_manual_record,
                    color: _isRecording ? Colors.white : Colors.red,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleDetectionResults(List<YOLOResult>? results) {
    if (!mounted) return;

    // Debug: print detection count
    if (_frameCount % 30 == 0) {
      print(
        'Live detector: ${results?.length ?? 0} detections in frame $_frameCount',
      );
      for (var r in results ?? []) {
        print('  - ${r.className} (${r.confidence.toStringAsFixed(2)})');
      }
    }

    setState(() {
      _detections = results ?? [];
      _frameCount++;

      // Find ball and hoop - handle null case
      YOLOResult? ballResult;
      YOLOResult? hoopResult;

      try {
        ballResult = results?.firstWhere(
          (r) => r.className.toLowerCase().contains('ball'),
        );
      } catch (e) {
        ballResult = null;
      }

      try {
        hoopResult = results!.firstWhere(
          (r) =>
              r.className.toLowerCase().contains('hoop') ||
              r.className.toLowerCase().contains('rim') ||
              r.className.toLowerCase().contains('basket'),
        );
      } catch (e) {
        hoopResult = null;
      }

      _isBallDetected = ballResult != null;
      _isHoopDetected = hoopResult != null;

      // Track ball position for trajectory analysis
      if (ballResult != null) {
        final box = ballResult.boundingBox;
        final ballCenter = Offset(
          box.left + box.width / 2,
          box.top + box.height / 2,
        );

        _currentBallPosition = ballCenter;
        _currentBallSize = box.width;

        // Add to trajectory with timestamp
        _ballTrajectory.add(ballCenter);
        _trajectoryTimestamps.add(DateTime.now());

        // Keep only recent trajectory (last 30 points / ~1 second at 30fps)
        if (_ballTrajectory.length > 30) {
          _ballTrajectory.removeAt(0);
          _trajectoryTimestamps.removeAt(0);
        }

        // Detect if shot is in progress (ball moving upward)
        if (_ballTrajectory.length >= 3) {
          final recentPoints = _ballTrajectory.sublist(
            _ballTrajectory.length - 3,
          );
          final isMovingUp =
              recentPoints[0].dy > recentPoints[1].dy &&
              recentPoints[1].dy > recentPoints[2].dy;

          if (isMovingUp && !_shotInProgress) {
            _shotInProgress = true;
            _analyzeLiveShot();
          }
        }
      } else {
        // Reset if ball lost
        if (_shotInProgress && _ballTrajectory.length > 10) {
          _shotInProgress = false;
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                _liveAnalysis = '';
                _predictedAccuracy = null;
                _ballTrajectory.clear();
                _trajectoryTimestamps.clear();
              });
            }
          });
        }
      }

      // Track hoop position
      if (hoopResult != null) {
        final box = hoopResult.boundingBox;
        _currentHoopPosition = Offset(
          box.left + box.width / 2,
          box.top + box.height / 2,
        );
        _currentHoopSize = box.width;
      }

      // Record frame if recording is active
      if (_isRecording) {
        _recordedFrames.add(
          RecordedFrame(
            timestamp: DateTime.now(),
            ballPosition: _currentBallPosition,
            hoopPosition: _currentHoopPosition,
            ballSize: _currentBallSize,
            hoopSize: _currentHoopSize,
          ),
        );
      }

      // Update analysis if shot in progress
      if (_shotInProgress && _isBallDetected && _isHoopDetected) {
        _analyzeLiveShot();
      }
    });
  }

  void _analyzeLiveShot() {
    if (_ballTrajectory.length < 5 || _currentHoopPosition == null) return;

    // Simple trajectory prediction
    final recentBall = _ballTrajectory.last;
    final hoopPos = _currentHoopPosition!;

    // Calculate horizontal distance from hoop
    final horizontalDistance = (recentBall.dx - hoopPos.dx).abs();

    // Calculate vertical trajectory (is ball going up?)
    final lastFew = _ballTrajectory.sublist(_ballTrajectory.length - 5);
    final avgYChange = (lastFew.last.dy - lastFew.first.dy) / 5;

    // Predict accuracy based on alignment
    final maxDistance = 200.0; // pixels
    _predictedAccuracy = ((1 - (horizontalDistance / maxDistance)) * 100).clamp(
      0,
      100,
    );

    // Generate live feedback
    if (horizontalDistance < 50) {
      if (avgYChange < -5) {
        _liveAnalysis = '✅ Great arc! Ball aligned with hoop';
      } else {
        _liveAnalysis = '📐 Arc too flat - shoot higher';
      }
    } else if (recentBall.dx < hoopPos.dx) {
      _liveAnalysis = '⬅️ Aim ${horizontalDistance.toInt()}px RIGHT';
    } else {
      _liveAnalysis = '➡️ Aim ${horizontalDistance.toInt()}px LEFT';
    }
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

  void _toggleRecording() {
    setState(() {
      if (_isRecording) {
        // Stop recording and save the shot
        _stopRecording();
      } else {
        // Start recording
        _startRecording();
      }
    });
  }

  void _startRecording() {
    _isRecording = true;
    _recordedFrames.clear();
    _recordingStartTime = DateTime.now();
  }

  void _stopRecording() {
    _isRecording = false;

    if (_recordedFrames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No frames recorded'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Create recorded shot
    final shot = RecordedShot(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      recordedAt: _recordingStartTime ?? DateTime.now(),
      frames: List.from(_recordedFrames),
      screenSize: MediaQuery.of(context).size,
      analysis: _liveAnalysis.isNotEmpty ? _liveAnalysis : null,
      predictedAccuracy: _predictedAccuracy,
    );

    _recordedShots.add(shot);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Shot recorded (${_recordedFrames.length} frames)'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () => _viewRecordedShot(shot),
        ),
      ),
    );
  }

  void _showRecordedShotsList() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView.builder(
          itemCount: _recordedShots.length,
          itemBuilder: (context, index) {
            final shot = _recordedShots[index];
            return ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text('Shot ${index + 1}'),
              subtitle: Text(
                '${shot.frames.length} frames · ${shot.duration.inSeconds}s',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () {
                  setState(() {
                    _recordedShots.removeAt(index);
                  });
                  Navigator.pop(context);
                },
              ),
              onTap: () {
                Navigator.pop(context);
                _viewRecordedShot(shot);
              },
            );
          },
        );
      },
    );
  }

  void _viewRecordedShot(RecordedShot shot) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ShotReplayViewer(shot: shot)),
    );
  }
}

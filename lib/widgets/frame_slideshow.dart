import 'dart:io';
import 'package:flutter/material.dart';

class FrameSlideshow extends StatefulWidget {
  final List<Map<String, dynamic>> frameData;

  const FrameSlideshow({
    super.key,
    required this.frameData,
  });

  @override
  State<FrameSlideshow> createState() => _FrameSlideshowState();
}

class _FrameSlideshowState extends State<FrameSlideshow> {
  int currentFrameIndex = 0;
  bool isAutoPlaying = false;

  void _nextFrame() {
    if (currentFrameIndex < widget.frameData.length - 1) {
      setState(() {
        currentFrameIndex++;
      });
    }
  }

  void _previousFrame() {
    if (currentFrameIndex > 0) {
      setState(() {
        currentFrameIndex--;
      });
    }
  }

  void _goToFrame(int index) {
    setState(() {
      currentFrameIndex = index.clamp(0, widget.frameData.length - 1);
    });
  }

  Widget _buildFrameImage() {
    if (widget.frameData.isEmpty) {
      return const Center(
        child: Text('No frames available'),
      );
    }

    final frameInfo = widget.frameData[currentFrameIndex];
    final framePath = frameInfo['path'] as String;
    final frameFile = File(framePath);

    if (!frameFile.existsSync()) {
      return Center(
        child: Text('Frame file not found: $framePath'),
      );
    }

    return Column(
      children: [
        // Frame metadata
        Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Frame ${frameInfo['frame_index']} / ${widget.frameData.length - 1}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Text(
                'Timestamp: ${frameInfo['timestamp'].toStringAsFixed(2)}s',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                'File: ${frameInfo['filename']}',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                'Size: ${frameFile.lengthSync()} bytes',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                'Path: $framePath',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Frame image
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                frameFile,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 48),
                        const SizedBox(height: 8),
                        Text('Error loading frame: $error'),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Navigation buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: currentFrameIndex > 0 ? () => _goToFrame(0) : null,
                icon: const Icon(Icons.first_page),
                tooltip: 'First frame',
              ),
              IconButton(
                onPressed: currentFrameIndex > 0 ? _previousFrame : null,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous frame',
              ),
              IconButton(
                onPressed: currentFrameIndex < widget.frameData.length - 1 ? _nextFrame : null,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next frame',
              ),
              IconButton(
                onPressed: currentFrameIndex < widget.frameData.length - 1
                    ? () => _goToFrame(widget.frameData.length - 1)
                    : null,
                icon: const Icon(Icons.last_page),
                tooltip: 'Last frame',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Frame slider
          if (widget.frameData.isNotEmpty)
            Column(
              children: [
                Text('Frame: ${currentFrameIndex + 1} / ${widget.frameData.length}'),
                Slider(
                  value: currentFrameIndex.toDouble(),
                  min: 0,
                  max: (widget.frameData.length - 1).toDouble(),
                  divisions: widget.frameData.length - 1,
                  onChanged: (value) {
                    _goToFrame(value.round());
                  },
                ),
              ],
            ),

          const SizedBox(height: 16),

          // Quick jump buttons
          Wrap(
            spacing: 8,
            children: [
              for (int i = 0; i < widget.frameData.length; i += (widget.frameData.length / 10).ceil())
                ElevatedButton(
                  onPressed: () => _goToFrame(i),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: i == currentFrameIndex ? Colors.blue : Colors.grey[300],
                  ),
                  child: Text('${i + 1}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Frame Slideshow'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Frame Analysis'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total frames: ${widget.frameData.length}'),
                      const SizedBox(height: 8),
                      if (widget.frameData.isNotEmpty) ...[
                        Text('First frame: ${widget.frameData.first['timestamp'].toStringAsFixed(2)}s'),
                        Text('Last frame: ${widget.frameData.last['timestamp'].toStringAsFixed(2)}s'),
                        const SizedBox(height: 8),
                        const Text('Use the controls below to navigate through frames and visually check if they are identical or different.'),
                      ],
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.info),
            tooltip: 'Frame info',
          ),
        ],
      ),
      body: widget.frameData.isEmpty
          ? const Center(
              child: Text('No frames to display'),
            )
          : Column(
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _buildFrameImage(),
                  ),
                ),
                _buildControls(),
              ],
            ),
    );
  }
}
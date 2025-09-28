import 'package:hooplab/models/clip.dart';

class FrameIndexCache {
  List<double> _timestamps = [];
  bool _isBuilt = false;

  void buildCache(List<FrameData> frames) {
    _timestamps = frames.map((f) => f.timestamp).toList();
    _isBuilt = true;
  }

  int findClosestFrame(double timestamp) {
    if (!_isBuilt || _timestamps.isEmpty) return 0;

    // Binary search for closest timestamp
    int left = 0, right = _timestamps.length - 1;
    int closest = 0;
    double minDiff = double.infinity;

    while (left <= right) {
      int mid = (left + right) ~/ 2;
      double diff = (_timestamps[mid] - timestamp).abs();

      if (diff < minDiff) {
        minDiff = diff;
        closest = mid;
      }

      if (_timestamps[mid] < timestamp) {
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }

    return closest;
  }

  int findPreviousFrame(double timestamp) {
    if (!_isBuilt || _timestamps.isEmpty) return 0;

    int left = 0, right = _timestamps.length - 1;
    int result = 0;

    while (left <= right) {
      int mid = (left + right) ~/ 2;

      if (_timestamps[mid] <= timestamp) {
        result = mid;
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }

    return result;
  }

  int findNextFrame(double timestamp) {
    if (!_isBuilt || _timestamps.isEmpty) return 0;

    int left = 0, right = _timestamps.length - 1;
    int result = _timestamps.length - 1;

    while (left <= right) {
      int mid = (left + right) ~/ 2;

      if (_timestamps[mid] >= timestamp) {
        result = mid;
        right = mid - 1;
      } else {
        left = mid + 1;
      }
    }

    return result;
  }

  void clear() {
    _timestamps.clear();
    _isBuilt = false;
  }

  bool get isBuilt => _isBuilt;
  int get frameCount => _timestamps.length;
}
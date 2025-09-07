import 'dart:math';

import 'package:flutter/widgets.dart';

class Detection {
  int trackId;
  Rect bbox;
  double confidence;
  Detection({
    required this.trackId,
    required this.bbox,
    required this.confidence,
  });
}

class Track {
  int id;
  Rect bbox;
  int framesMissing = 0;
  Track({required this.id, required this.bbox});
}

class BasketballTracker {
  final double maxDistance;
  final int maxFramesMissing;
  int nextTrackId = 0;
  final Map<int, Track> tracks = {};

  BasketballTracker({this.maxDistance = 100, this.maxFramesMissing = 10});

  List<Detection> update(List<Rect> detectedBBoxes) {
    final List<Detection> output = [];

    final unmatchedTracks = <int>{...tracks.keys};
    final matchedTracks = <int>{};

    for (final det in detectedBBoxes) {
      Track? bestTrack;
      double minDist = double.infinity;

      for (final track in tracks.values) {
        final dx = track.bbox.center.dx - det.center.dx;
        final dy = track.bbox.center.dy - det.center.dy;
        final dist = sqrt((dx * dx + dy * dy));
        if (dist < minDist && dist < maxDistance) {
          minDist = dist;
          bestTrack = track;
        }
      }

      if (bestTrack != null) {
        // Update existing track
        bestTrack.bbox = det;
        bestTrack.framesMissing = 0;
        unmatchedTracks.remove(bestTrack.id);
        matchedTracks.add(bestTrack.id);

        output.add(
          Detection(trackId: bestTrack.id, bbox: det, confidence: 1.0),
        );
      } else {
        // Create new track
        final id = nextTrackId++;
        final track = Track(id: id, bbox: det);
        tracks[id] = track;
        matchedTracks.add(id);

        output.add(Detection(trackId: id, bbox: det, confidence: 1.0));
      }
    }

    // Increment framesMissing for unmatched tracks
    for (final tid in unmatchedTracks) {
      final track = tracks[tid]!;
      track.framesMissing += 1;
      if (track.framesMissing > maxFramesMissing) tracks.remove(tid);
    }

    return output;
  }
}

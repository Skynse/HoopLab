import 'dart:io';
import 'dart:typed_data';

class VideoMetadata {
  final double fps;
  final double duration;
  final int width;
  final int height;
  final int totalFrames;

  VideoMetadata({
    required this.fps,
    required this.duration,
    required this.width,
    required this.height,
    required this.totalFrames,
  });
}

class VideoMetadataParser {
  /// Parse video metadata from binary data
  static Future<VideoMetadata?> parseFromFile(String filePath) async {
    try {
      print('🎬 Parsing video metadata from: $filePath');
      final file = File(filePath);
      if (!await file.exists()) {
        print('❌ Video file does not exist: $filePath');
        return null;
      }

      final bytes = await file.readAsBytes();
      print('📊 File size: ${bytes.length} bytes');

      // Try MP4 first (most common)
      print('🔍 Trying MP4 format...');
      final mp4Data = _parseMP4(bytes);
      if (mp4Data != null) {
        print('✅ Successfully parsed as MP4');
        return mp4Data;
      }

      // Try MOV format
      print('🔍 Trying MOV format...');
      final movData = _parseMOV(bytes);
      if (movData != null) {
        print('✅ Successfully parsed as MOV');
        return movData;
      }

      // Try AVI format
      print('🔍 Trying AVI format...');
      final aviData = _parseAVI(bytes);
      if (aviData != null) {
        print('✅ Successfully parsed as AVI');
        return aviData;
      }

      print('❌ Could not parse video in any supported format');
      return null;
    } catch (e) {
      print('Error parsing video metadata: $e');
      return null;
    }
  }

  /// Parse MP4/M4V format
  static VideoMetadata? _parseMP4(Uint8List bytes) {
    try {
      double? fps;
      double? duration;
      int? width, height;

      // Look for key MP4 atoms
      for (int i = 0; i < bytes.length - 8; i++) {
        final atomSize = _readUint32BE(bytes, i);
        if (atomSize == 0 || atomSize > bytes.length - i) continue;

        final atomType = String.fromCharCodes(bytes.sublist(i + 4, i + 8));

        switch (atomType) {
          case 'mvhd': // Movie header
            if (i + 32 < bytes.length) {
              final timeScale = _readUint32BE(bytes, i + 20);
              final durationTicks = _readUint32BE(bytes, i + 24);
              if (timeScale > 0) {
                duration = durationTicks / timeScale;
              }
            }
            break;

          case 'tkhd': // Track header (video track)
            if (i + 84 < bytes.length) {
              width = _readUint32BE(bytes, i + 76) >> 16; // Fixed point 16.16
              height = _readUint32BE(bytes, i + 80) >> 16;
            }
            break;

          case 'stts': // Sample time table (for FPS calculation)
            if (i + 16 < bytes.length) {
              final entryCount = _readUint32BE(bytes, i + 12);
              if (entryCount > 0 && i + 20 < bytes.length) {
                final sampleCount = _readUint32BE(bytes, i + 16);
                final sampleDelta = _readUint32BE(bytes, i + 20);
                if (sampleDelta > 0) {
                  // Approximate FPS calculation
                  fps = 1000.0 / (sampleDelta / 1000.0);
                }
              }
            }
            break;
        }

        i += atomSize.toInt() - 1;
      }

      // Apply defaults if we got partial data
      fps ??= 30.0;
      duration ??= 0.0;
      width ??= 1920;
      height ??= 1080;

      final totalFrames = (fps * duration).round();

      if (duration > 0) {
        return VideoMetadata(
          fps: fps,
          duration: duration,
          width: width,
          height: height,
          totalFrames: totalFrames,
        );
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Parse MOV format (similar to MP4)
  static VideoMetadata? _parseMOV(Uint8List bytes) {
    // MOV uses same atom structure as MP4
    return _parseMP4(bytes);
  }

  /// Parse AVI format
  static VideoMetadata? _parseAVI(Uint8List bytes) {
    try {
      // Look for AVI signature
      if (bytes.length < 12) return null;

      final riffSignature = String.fromCharCodes(bytes.sublist(0, 4));
      final aviSignature = String.fromCharCodes(bytes.sublist(8, 12));

      if (riffSignature != 'RIFF' || aviSignature != 'AVI ') return null;

      // Look for 'avih' header
      for (int i = 12; i < bytes.length - 56; i++) {
        final chunkId = String.fromCharCodes(bytes.sublist(i, i + 4));
        if (chunkId == 'avih') {
          final microSecPerFrame = _readUint32LE(bytes, i + 8);
          final totalFrames = _readUint32LE(bytes, i + 16);
          final width = _readUint32LE(bytes, i + 32);
          final height = _readUint32LE(bytes, i + 36);

          if (microSecPerFrame > 0) {
            final fps = 1000000.0 / microSecPerFrame;
            final duration = totalFrames / fps;

            return VideoMetadata(
              fps: fps,
              duration: duration,
              width: width.toInt(),
              height: height.toInt(),
              totalFrames: totalFrames.toInt(),
            );
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Read 32-bit big-endian integer
  static int _readUint32BE(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
           (bytes[offset + 1] << 16) |
           (bytes[offset + 2] << 8) |
           bytes[offset + 3];
  }

  /// Read 32-bit little-endian integer
  static int _readUint32LE(Uint8List bytes, int offset) {
    return bytes[offset] |
           (bytes[offset + 1] << 8) |
           (bytes[offset + 2] << 16) |
           (bytes[offset + 3] << 24);
  }

  /// Quick check if file format is supported
  static Future<String?> detectVideoFormat(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();

      if (bytes.length < 12) return null;

      // Check MP4/MOV
      final mp4Check = String.fromCharCodes(bytes.sublist(4, 8));
      if (mp4Check == 'ftyp') return 'MP4';

      // Check AVI
      final riffCheck = String.fromCharCodes(bytes.sublist(0, 4));
      final aviCheck = String.fromCharCodes(bytes.sublist(8, 12));
      if (riffCheck == 'RIFF' && aviCheck == 'AVI ') return 'AVI';

      // Check MOV (QuickTime)
      for (int i = 0; i < bytes.length - 8; i += 4) {
        final atomType = String.fromCharCodes(bytes.sublist(i + 4, i + 8));
        if (atomType == 'moov') return 'MOV';
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
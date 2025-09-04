import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

Future<Float32List> preprocessImage(Uint8List imageBytes) async {
  // Decode image
  final image = img.decodeImage(imageBytes);
  if (image == null) throw Exception('Failed to decode image');
  
  // Calculate aspect ratio preserving dimensions
  const targetSize = 640;
  final ratio = targetSize / math.max(image.width, image.height);
  final newWidth = (image.width * ratio).round();
  final newHeight = (image.height * ratio).round();
  
  // Resize maintaining aspect ratio
  final resized = img.copyResize(image, width: newWidth, height: newHeight);
  
  // Create a new 640x640 image with padding
  final paddedImage = img.Image(width: targetSize, height: targetSize);
  
  // Calculate padding
  final xOffset = ((targetSize - newWidth) / 2).round();
  final yOffset = ((targetSize - newHeight) / 2).round();
  
  // Copy resized image to center of padded image
  for (var y = 0; y < newHeight; y++) {
    for (var x = 0; x < newWidth; x++) {
      paddedImage.setPixel(x + xOffset, y + yOffset, resized.getPixel(x, y));
    }
  }
  
  // Convert to float32 and normalize to [0,1]
  final inputTensor = Float32List(1 * 3 * targetSize * targetSize);
  var idx = 0;
  
  // Convert RGB and normalize
  for (var y = 0; y < targetSize; y++) {
    for (var x = 0; x < targetSize; x++) {
      final pixel = paddedImage.getPixel(x, y);
      
      // Get RGB values and normalize to [0,1]
      inputTensor[idx] = pixel.r.toDouble() / 255.0;
      inputTensor[idx + targetSize * targetSize] = pixel.g.toDouble() / 255.0;
      inputTensor[idx + 2 * targetSize * targetSize] = pixel.b.toDouble() / 255.0;
      idx++;
    }
  }
  
  return inputTensor;
}

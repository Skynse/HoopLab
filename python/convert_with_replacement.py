from ultralytics import YOLO
import onnx2tf
import os

def convert_yolo_with_replacement():
    """Convert YOLO model to TFLite using onnx2tf with parameter replacement."""

    # Load YOLO model
    model = YOLO('best.pt')

    # Step 1: Export to ONNX first (if not already done)
    onnx_path = 'best.onnx'
    if not os.path.exists(onnx_path):
        print("Exporting to ONNX...")
        model.export(format='onnx', imgsz=640, opset=11)
    else:
        print("ONNX file already exists, using existing file...")

    # Step 2: Convert ONNX to TensorFlow/TFLite using onnx2tf with parameter replacement
    print("Converting ONNX to TensorFlow/TFLite with parameter replacement...")

    try:
        # Convert with parameter replacement file
        keras_model = onnx2tf.convert(
            input_onnx_file_path='best.onnx',
            output_folder_path='saved_model_fixed',
            output_signaturedefs=True,
            output_integer_quantized_tflite=True,
            param_replacement_file='replace.json',
            batch_size=1,  # Fix dynamic batch size
            disable_strict_mode=True,  # Speed up conversion, may help with attention issues
            check_onnx_tf_outputs_elementwise_close_full=False,  # Disable accuracy checking during conversion
            custom_input_op_name_np_data_path=[
                ["images", "calibration_image_sample_data_20x128x128x3_float32.npy"]
            ] if os.path.exists("calibration_image_sample_data_20x128x128x3_float32.npy") else None,
            verbosity='info',  # Reduce log verbosity
            non_verbose=False
        )

        print("✅ Conversion successful!")
        print("📁 Output saved to: saved_model_fixed/")
        print("🏷️  TFLite models:")
        print("   - saved_model_fixed/best_float32.tflite")
        print("   - saved_model_fixed/best_float16.tflite")
        print("   - saved_model_fixed/best_integer_quant.tflite")

    except Exception as e:
        print(f"❌ Conversion failed with parameter replacement: {e}")
        print("\n🔧 Trying alternative approach with additional options...")

        # Try alternative approach with more options
        try:
            keras_model = onnx2tf.convert(
                input_onnx_file_path='best.onnx',
                output_folder_path='saved_model_alternative',
                output_signaturedefs=True,
                param_replacement_file='replace.json',
                batch_size=1,
                disable_strict_mode=True,
                replace_to_pseudo_operators=['Mul'],  # Replace problematic Mul with pseudo-ops
                optimization_for_gpu_delegate=True,
                verbosity='info'
            )
            print("✅ Alternative conversion successful!")
            print("📁 Output saved to: saved_model_alternative/")

        except Exception as e2:
            print(f"❌ Alternative conversion also failed: {e2}")
            print("\n💡 Suggestions:")
            print("1. Try auto-generating parameter replacement JSON:")
            print("   onnx2tf -i best.onnx -agj")
            print("2. Check the generated JSON and modify replace.json accordingly")
            print("3. Try without INT8 quantization first")

if __name__ == "__main__":
    convert_yolo_with_replacement()

#!/bin/bash

# ONNX2TF Conversion Troubleshooting Script
# This script helps fix the "Output tensors of a Functional model must be the output of a TensorFlow Layer" error
# Specifically designed for YOLO models with attention mechanism issues

set -e

echo "🎯 ONNX2TF Conversion Fix Script"
echo "================================"
echo "This script will help fix the Mul operation error in your YOLO model conversion"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required files exist
check_prerequisites() {
    print_status "Checking prerequisites..."

    if [ ! -f "best.onnx" ]; then
        print_error "best.onnx not found!"
        echo "Please run your initial conversion script to generate the ONNX file first."
        exit 1
    fi

    if ! command -v onnx2tf &> /dev/null; then
        print_error "onnx2tf not found!"
        echo "Please install onnx2tf: pip install onnx2tf"
        exit 1
    fi

    print_success "Prerequisites check passed"
}

# Method 1: Auto-generate parameter replacement JSON
method_1_auto_generate() {
    print_status "Method 1: Auto-generating parameter replacement JSON..."

    echo "This method automatically finds optimal parameters to fix conversion errors."

    # Try auto-generation with accuracy validation
    print_status "Attempting auto-generation with full validation..."
    if onnx2tf -i best.onnx -agj -cotof -b 1 -v info -o saved_model_auto 2>/dev/null; then
        print_success "Auto-generation with validation completed!"

        # Check if auto JSON was created
        if [ -f "best_auto.json" ]; then
            print_success "Auto-generated JSON found: best_auto.json"
            cp best_auto.json replace.json
            print_success "Copied to replace.json for use"
            return 0
        fi
    else
        print_warning "Auto-generation with validation failed, trying without validation..."

        # Try without accuracy checking
        if onnx2tf -i best.onnx -agj -b 1 -v info -o saved_model_auto_simple 2>/dev/null; then
            print_success "Auto-generation without validation completed!"

            if [ -f "best_auto.json" ]; then
                print_success "Auto-generated JSON found: best_auto.json"
                cp best_auto.json replace.json
                return 0
            fi
        fi
    fi

    print_warning "Auto-generation failed, proceeding to manual methods..."
    return 1
}

# Method 2: Manual parameter replacement for specific Mul operation
method_2_manual_replacement() {
    print_status "Method 2: Creating manual parameter replacement for Mul operation..."

    cat > replace.json << 'EOF'
{
  "format_version": 1,
  "operations": [
    {
      "op_name": "wa/model.10/m/m.0/attn/Mul",
      "param_target": "inputs",
      "pre_process_transpose_perm": [0, 1, 2, 3]
    },
    {
      "op_name": "wa/model.10/m/m.0/attn/Mul",
      "param_target": "outputs",
      "post_process_transpose_perm": [0, 1, 2, 3]
    }
  ]
}
EOF

    print_success "Created manual parameter replacement: replace.json"

    # Test the manual replacement
    print_status "Testing manual replacement..."
    if onnx2tf -i best.onnx -prf replace.json -b 1 -v info -o saved_model_manual 2>/dev/null; then
        print_success "Manual replacement test successful!"
        return 0
    else
        print_warning "Manual replacement test failed"
        return 1
    fi
}

# Method 3: Replace problematic operators with pseudo-operators
method_3_pseudo_operators() {
    print_status "Method 3: Using pseudo-operators to replace problematic Mul operations..."

    cat > replace_pseudo.json << 'EOF'
{
  "format_version": 1,
  "operations": [
    {
      "op_name": "wa/model.10/m/m.0/attn/Mul",
      "param_target": "op",
      "replace_to_pseudo_operators": ["Mul"]
    }
  ]
}
EOF

    print_success "Created pseudo-operator replacement: replace_pseudo.json"

    # Test with pseudo operators
    print_status "Testing with pseudo-operators..."
    if onnx2tf -i best.onnx -prf replace_pseudo.json -rtpo Mul -b 1 -v info -o saved_model_pseudo 2>/dev/null; then
        print_success "Pseudo-operator replacement successful!"
        cp replace_pseudo.json replace.json
        return 0
    else
        print_warning "Pseudo-operator replacement failed"
        return 1
    fi
}

# Method 4: Disable strict mode and use alternative settings
method_4_alternative_settings() {
    print_status "Method 4: Using alternative conversion settings..."

    print_status "Trying conversion with disabled strict mode..."
    if onnx2tf -i best.onnx -b 1 -dsm -v info -o saved_model_alt 2>/dev/null; then
        print_success "Alternative settings successful!"
        return 0
    fi

    print_status "Trying with GPU delegate optimization..."
    if onnx2tf -i best.onnx -b 1 -ofgd -v info -o saved_model_gpu 2>/dev/null; then
        print_success "GPU delegate optimization successful!"
        return 0
    fi

    print_warning "Alternative settings failed"
    return 1
}

# Method 5: Split model for debugging
method_5_split_model() {
    print_status "Method 5: Splitting model to isolate the problematic operation..."

    # Try to convert up to the problematic layer
    print_status "Converting model up to the problematic Mul operation..."
    if onnx2tf -i best.onnx -onimc "wa/model.10/m/m.0/attn/Mul" -b 1 -v info -o saved_model_split 2>/dev/null; then
        print_success "Partial model conversion successful!"
        print_status "This confirms the issue is with the specific Mul operation"
        return 0
    else
        print_warning "Model splitting failed"
        return 1
    fi
}

# Test final conversion with the working solution
test_final_conversion() {
    print_status "Testing final conversion with working solution..."

    local best_replace_file=""

    # Find the best working replacement file
    if [ -f "replace.json" ]; then
        best_replace_file="replace.json"
    elif [ -f "replace_pseudo.json" ]; then
        best_replace_file="replace_pseudo.json"
    fi

    if [ -n "$best_replace_file" ]; then
        print_status "Using replacement file: $best_replace_file"

        # Test basic conversion
        print_status "Testing basic TensorFlow SavedModel conversion..."
        if onnx2tf -i best.onnx -prf "$best_replace_file" -b 1 -osd -v info -o saved_model_final; then
            print_success "Basic conversion successful!"

            # Test TFLite conversion
            print_status "Testing TFLite conversion..."
            if onnx2tf -i best.onnx -prf "$best_replace_file" -b 1 -v info -o saved_model_tflite; then
                print_success "TFLite conversion successful!"

                # Test INT8 quantization if calibration data exists
                if [ -f "calibration_image_sample_data_20x128x128x3_float32.npy" ]; then
                    print_status "Testing INT8 quantization with calibration data..."
                    if onnx2tf -i best.onnx -prf "$best_replace_file" -oiqt -cind images calibration_image_sample_data_20x128x128x3_float32.npy -b 1 -v info -o saved_model_int8; then
                        print_success "INT8 quantization successful!"
                    else
                        print_warning "INT8 quantization failed, but float models work"
                    fi
                else
                    print_warning "No calibration data found, skipping INT8 quantization test"
                fi

                return 0
            fi
        fi
    else
        # Try without replacement file
        print_status "No replacement file available, trying direct conversion with alternative options..."
        if onnx2tf -i best.onnx -b 1 -dsm -rtpo Mul -v info -o saved_model_direct; then
            print_success "Direct conversion with alternative options successful!"
            return 0
        fi
    fi

    return 1
}

# Main execution flow
main() {
    check_prerequisites

    echo ""
    print_status "Starting troubleshooting process..."
    echo ""

    # Try each method in order
    if method_1_auto_generate; then
        print_success "Method 1 (Auto-generate) worked!"
    elif method_2_manual_replacement; then
        print_success "Method 2 (Manual replacement) worked!"
    elif method_3_pseudo_operators; then
        print_success "Method 3 (Pseudo-operators) worked!"
    elif method_4_alternative_settings; then
        print_success "Method 4 (Alternative settings) worked!"
    elif method_5_split_model; then
        print_success "Method 5 (Model splitting) worked!"
    else
        print_error "All automated methods failed!"
        echo ""
        echo "Manual troubleshooting suggestions:"
        echo "1. Check ONNX model structure: onnx2tf -i best.onnx -v debug"
        echo "2. Try different opset versions when exporting from YOLO"
        echo "3. Simplify model structure before conversion"
        echo "4. Check for dynamic dimensions: use -ois option"
        echo "5. Consider using nobuco or ai-edge-torch as alternatives"
        exit 1
    fi

    echo ""
    print_status "Testing final conversion with working solution..."

    if test_final_conversion; then
        echo ""
        print_success "🎉 CONVERSION SUCCESSFUL!"
        echo ""
        echo "Generated files:"
        echo "- saved_model_final/ (TensorFlow SavedModel)"
        echo "- saved_model_final/best_float32.tflite (Float32 TFLite)"
        echo "- saved_model_final/best_float16.tflite (Float16 TFLite)"
        if [ -d "saved_model_int8" ]; then
            echo "- saved_model_int8/best_integer_quant.tflite (INT8 TFLite)"
        fi
        echo ""
        echo "Parameter replacement file used: replace.json"
        echo ""
        echo "You can now use these models for inference!"
    else
        print_warning "Final conversion test failed, but intermediate steps worked"
        echo "Check the generated saved_model directories for partial results"
    fi
}

# Run the main function
main "$@"

#!/usr/bin/env python3
"""
Auto-generate parameter replacement JSON for onnx2tf conversion.
This script will automatically find the optimal parameter replacement settings
to fix conversion errors like the Mul operation issue in YOLO models.
"""

import os
import subprocess
import sys
import json
from pathlib import Path

def run_command(cmd, description=""):
    """Run a command and return success status."""
    print(f"🔄 {description}")
    print(f"Command: {cmd}")

    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode == 0:
            print(f"✅ {description} - Success")
            return True, result.stdout, result.stderr
        else:
            print(f"❌ {description} - Failed")
            print(f"Error: {result.stderr}")
            return False, result.stdout, result.stderr
    except Exception as e:
        print(f"❌ {description} - Exception: {e}")
        return False, "", str(e)

def auto_generate_replacement_json():
    """Auto-generate parameter replacement JSON using onnx2tf."""

    onnx_file = 'best.onnx'

    # Check if ONNX file exists
    if not os.path.exists(onnx_file):
        print(f"❌ ONNX file '{onnx_file}' not found!")
        print("Please run the initial conversion to create the ONNX file first.")
        return False

    print("🚀 Starting auto-generation of parameter replacement JSON...")
    print(f"📄 Input file: {onnx_file}")

    # Step 1: Auto-generate JSON with accuracy validation
    cmd = f"onnx2tf -i {onnx_file} -agj -cotof -b 1 -v info"
    success, stdout, stderr = run_command(cmd, "Auto-generating parameter replacement JSON")

    if not success:
        print("\n🔧 Trying alternative auto-generation without accuracy validation...")
        # Try without full accuracy checking which might be causing issues
        cmd = f"onnx2tf -i {onnx_file} -agj -b 1 -v info"
        success, stdout, stderr = run_command(cmd, "Auto-generating JSON (alternative)")

    # Check if auto-generated JSON was created
    auto_json_file = f"{Path(onnx_file).stem}_auto.json"

    if os.path.exists(auto_json_file):
        print(f"✅ Auto-generated JSON created: {auto_json_file}")

        # Read and display the generated JSON
        try:
            with open(auto_json_file, 'r') as f:
                auto_json = json.load(f)

            print("\n📋 Generated parameter replacements:")
            print(json.dumps(auto_json, indent=2))

            # Copy to replace.json for easy use
            with open('replace.json', 'w') as f:
                json.dump(auto_json, f, indent=2)

            print(f"\n✅ Copied auto-generated JSON to 'replace.json'")
            return True

        except Exception as e:
            print(f"❌ Error reading auto-generated JSON: {e}")
            return False
    else:
        print(f"❌ Auto-generated JSON file '{auto_json_file}' was not created")
        print("\n🔧 Creating manual fix for the specific Mul operation error...")

        # Create a manual fix for the known Mul operation issue
        manual_fix = {
            "format_version": 1,
            "operations": [
                {
                    "op_name": "wa/model.10/m/m.0/attn/Mul",
                    "param_target": "op",
                    "replace_to_pseudo_operators": ["Mul"]
                },
                {
                    "op_name": "wa/model.10/m/m.0/attn/Mul",
                    "param_target": "inputs",
                    "pre_process_transpose_perm": [0, 1, 2, 3]
                }
            ]
        }

        with open('replace_manual.json', 'w') as f:
            json.dump(manual_fix, f, indent=2)

        print("✅ Created manual replacement file: replace_manual.json")
        return True

def test_conversion_with_replacement():
    """Test the conversion using the generated replacement file."""

    replacement_files = ['replace.json', 'replace_manual.json']

    for replace_file in replacement_files:
        if not os.path.exists(replace_file):
            continue

        print(f"\n🧪 Testing conversion with {replace_file}...")

        # Test conversion with the replacement file
        cmd = f"onnx2tf -i best.onnx -prf {replace_file} -b 1 -osd -v info -o saved_model_test"
        success, stdout, stderr = run_command(cmd, f"Testing conversion with {replace_file}")

        if success:
            print(f"✅ Conversion successful with {replace_file}!")
            return True
        else:
            print(f"❌ Conversion failed with {replace_file}")
            continue

    return False

def main():
    """Main function to auto-generate and test parameter replacement."""

    print("🎯 Auto-Generate Parameter Replacement for onnx2tf")
    print("=" * 50)

    # Step 1: Auto-generate replacement JSON
    if auto_generate_replacement_json():
        print("\n" + "=" * 50)

        # Step 2: Test the conversion
        if test_conversion_with_replacement():
            print("\n🎉 SUCCESS! Parameter replacement working correctly.")
            print("\n📋 Next steps:")
            print("1. Use the generated replace.json in your conversion")
            print("2. For INT8 quantization, add calibration data:")
            print("   onnx2tf -i best.onnx -prf replace.json -oiqt -cind images calibration_data.npy")
            print("3. For TFLite export:")
            print("   onnx2tf -i best.onnx -prf replace.json -b 1 -osd")
        else:
            print("\n⚠️  Parameter replacement generated but conversion still failing.")
            print("\n🔧 Additional troubleshooting options:")
            print("1. Try disabling strict mode: -dsm")
            print("2. Try replacing problematic operators: -rtpo Mul")
            print("3. Check model structure with: onnx2tf -i best.onnx -inimc images -onimc output")

    else:
        print("\n❌ Failed to generate parameter replacement.")
        print("\n💡 Manual troubleshooting suggestions:")
        print("1. Verify ONNX file is valid")
        print("2. Try simplifying the model first")
        print("3. Check input dimensions and batch size")

if __name__ == "__main__":
    main()

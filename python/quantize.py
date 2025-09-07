# quantization script

model_path = "best_quant.tflite"

import tensorflow as tf
import numpy as np


converter = tf.lite.TFLiteConverter.from_saved_model("saved_model")
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_quant_model = converter.convert()

with open(model_path, "wb") as f:
    f.write(tflite_quant_model)
print(f"Quantized model saved to {model_path}")
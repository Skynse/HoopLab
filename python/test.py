import tensorflow as tf
import numpy as np
from PIL import Image

# Load the TensorFlow Lite model
interpreter = tf.lite.Interpreter(model_path="saved_model/best_float16.tflite")
interpreter.allocate_tensors()

# Get input and output tensors
input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

# Load and preprocess the image
image = Image.open("bus.jpg")
image = image.convert('RGB')

# Get input shape from the model
input_shape = input_details[0]['shape']
height, width = input_shape[1], input_shape[2]

# Resize image to match model input
image = image.resize((width, height))

# Convert to numpy array and normalize
input_data = np.array(image, dtype=np.float32)
input_data = np.expand_dims(input_data, axis=0)
input_data = input_data / 255.0

# Set input tensor
interpreter.set_tensor(input_details[0]['index'], input_data)

# Run inference
interpreter.invoke()

# Get output
output_data = interpreter.get_tensor(output_details[0]['index'])

print("Model input shape:", input_shape)
print("Output shape:", output_data.shape)
print("Predictions:", output_data)

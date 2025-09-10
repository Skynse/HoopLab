# HoopLab set up

## Setup Instructions

### 1. Start the Python Server

1. Navigate to the Python directory:
   ```bash
   cd python
   ```

3. Run the server:
   ```bash
   python server2.py
   ```

if that doesn't work, use python3

The server will start on `http://0.0.0.0:8080`

### 2. Configure the Flutter App

1. Find your computer's IP address:
   - **Windows**: Open Command Prompt, type `ipconfig`, look for "IPv4 Address"
   - **Mac**: Open Terminal, type `ifconfig`, look for "inet" under your network interface
   - **Linux**: Open Terminal, type `hostname -I`

2. Update the server IP in the Flutter app:
   - Open `lib/viewer.dart` (or wherever your main code is)
   - Find this line:
     ```dart
     var endpoint = "http://192.168.1.10:8080/extract_frames/";
     ```
   - Replace `192.168.1.10` with your computer's IP address

### 3. Run the Flutter App

1. Connect your device or start an emulator
2. Run the app:
   ```bash
   flutter run
   ```

## Usage

1. The app will load a video file
2. Tap "Start Analysis" to begin processing
3. The server extracts frames and sends them back to the app
4. The app runs YOLO detection on each frame
5. View detected objects overlaid on the video

## Troubleshooting

- **Connection Error**: Make sure both your phone and computer are on the same WiFi network
- **Server Not Found**: Double-check the IP address in the Flutter code matches your computer's IP
- **Port Already in Use**: If port 8080 is busy, change it in `server2.py` and update the Flutter code accordingly
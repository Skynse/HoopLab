import cv2
import fastapi
from fastapi.responses import StreamingResponse
import asyncio
import zipfile
import json
import tempfile
from pathlib import Path
import io
import concurrent.futures
from typing import List, Tuple
import numpy as np

app = fastapi.FastAPI()

# Thread pool for CPU-intensive operations
executor = concurrent.futures.ThreadPoolExecutor(max_workers=4)

def process_frame_batch(frames: List[Tuple[int, np.ndarray]], quality: int, compression_level: int = 6) -> List[Tuple[str, bytes]]:
    """Process a batch of frames in parallel"""
    results = []
    encode_params = [cv2.IMWRITE_JPEG_QUALITY, quality, cv2.IMWRITE_JPEG_OPTIMIZE, 1]
    
    for frame_idx, frame in frames:
        # Encode frame to JPEG
        _, buffer = cv2.imencode('.jpg', frame, encode_params)
        filename = f"frame_{frame_idx:06d}.jpg"
        results.append((filename, buffer.tobytes()))
    
    return results

async def extract_frames_streaming(video_data: bytes, quality: int = 70, skip_frames: int = 1):
    """Extract frames and stream zip directly without disk storage"""
    
    # Create in-memory buffer for zip
    zip_buffer = io.BytesIO()
    
    # Write video data to temporary file (unavoidable for OpenCV)
    with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as temp_video:
        temp_video.write(video_data)
        temp_video_path = temp_video.name
    
    try:
        cap = cv2.VideoCapture(temp_video_path)
        if not cap.isOpened():
            raise fastapi.HTTPException(status_code=400, detail="Could not open video file")

        # Get video properties
        fps = cap.get(cv2.CAP_PROP_FPS)
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

        # Create zip file in memory with faster compression
        with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zipf:
            
            frame_idx = 0
            extracted_count = 0
            frame_batch = []
            batch_size = 50  # Process frames in batches
            
            while True:
                ret, frame = cap.read()
                if not ret:
                    break
                
                # Skip frames if specified (reduces processing time)
                if frame_idx % (skip_frames + 1) == 0:
                    frame_batch.append((extracted_count, frame))
                    extracted_count += 1
                    
                    # Process batch when it's full
                    if len(frame_batch) >= batch_size:
                        # Process batch in thread pool
                        loop = asyncio.get_event_loop()
                        processed_frames = await loop.run_in_executor(
                            executor, process_frame_batch, frame_batch, quality
                        )
                        
                        # Add to zip
                        for filename, frame_data in processed_frames:
                            zipf.writestr(filename, frame_data)
                        
                        frame_batch = []
                
                frame_idx += 1
            
            # Process remaining frames
            if frame_batch:
                loop = asyncio.get_event_loop()
                processed_frames = await loop.run_in_executor(
                    executor, process_frame_batch, frame_batch, quality
                )
                for filename, frame_data in processed_frames:
                    zipf.writestr(filename, frame_data)

            # Create optimized metadata
            metadata = {
                "fps": fps,
                "total_frames": total_frames,
                "extracted_frames": extracted_count,
                "width": width,
                "height": height,
                "skip_frames": skip_frames
            }
            
            # Add metadata to zip
            zipf.writestr("metadata.json", json.dumps(metadata, separators=(',', ':')))

        cap.release()
        
    finally:
        # Clean up temp video file
        try:
            Path(temp_video_path).unlink()
        except:
            pass
    
    # Reset buffer position for reading
    zip_buffer.seek(0)
    return zip_buffer

@app.post("/extract_frames/")
async def extract_frames_zip(
    file: fastapi.UploadFile,
    quality: int = 70,  # Reduced default quality for speed
    skip_frames: int = 0  # Skip every N frames (0 = extract all)
):
    """
    Extract frames from video and return as streaming zip
    
    Args:
        file: Video file
        quality: JPEG quality (1-100, lower = faster)
        skip_frames: Skip every N frames (0 = all frames, 1 = every other frame, etc.)
    """
    # Read file data once
    video_data = await file.read()
    
    # Generate zip stream
    zip_buffer = await extract_frames_streaming(video_data, quality, skip_frames)
    
    # Stream the zip file directly
    def generate():
        while True:
            chunk = zip_buffer.read(8192)  # 8KB chunks
            if not chunk:
                break
            yield chunk
    
    filename = f"{Path(file.filename).stem}_frames.zip"
    
    return StreamingResponse(
        generate(),
        media_type="application/zip",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )

@app.post("/extract_frames_fast/")
async def extract_frames_fast(
    file: fastapi.UploadFile,
    max_frames: int = 100,  # Limit number of frames
    quality: int = 60       # Lower quality for speed
):
    """
    Ultra-fast frame extraction with limits for mobile apps
    """
    video_data = await file.read()
    
    with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as temp_video:
        temp_video.write(video_data)
        temp_video_path = temp_video.name
    
    try:
        cap = cv2.VideoCapture(temp_video_path)
        if not cap.isOpened():
            raise fastapi.HTTPException(status_code=400, detail="Could not open video file")

        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        fps = cap.get(cv2.CAP_PROP_FPS)
        
        # Calculate frame skip to stay under max_frames
        skip_factor = max(1, total_frames // max_frames)
        
        zip_buffer = io.BytesIO()
        extracted_count = 0
        
        with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED, compresslevel=1) as zipf:
            frame_idx = 0
            
            while True:
                ret, frame = cap.read()
                if not ret or extracted_count >= max_frames:
                    break
                
                if frame_idx % skip_factor == 0:
                    # Quick JPEG encoding with minimal quality
                    _, buffer = cv2.imencode('.jpg', frame, [
                        cv2.IMWRITE_JPEG_QUALITY, quality,
                        cv2.IMWRITE_JPEG_OPTIMIZE, 0  # Disable optimization for speed
                    ])
                    
                    filename = f"frame_{extracted_count:04d}.jpg"
                    zipf.writestr(filename, buffer.tobytes())
                    extracted_count += 1
                
                frame_idx += 1
            
            # Keep exact same metadata format as original
            metadata = {
                "fps": fps,
                "total_frames": total_frames,
                "extracted_frames": extracted_count,
                "width": int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)),
                "height": int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)),
                "frames": [
                    {
                        "frame_index": i,
                        "timestamp": (i * skip_factor) / fps if fps > 0 else 0.0,
                        "filename": f"frame_{i:04d}.jpg"
                    }
                    for i in range(extracted_count)
                ]
            }
            zipf.writestr("metadata.json", json.dumps(metadata, separators=(',', ':')))

        cap.release()
        
    finally:
        try:
            Path(temp_video_path).unlink()
        except:
            pass
    
    zip_buffer.seek(0)
    
    def generate():
        while True:
            chunk = zip_buffer.read(16384)  # Larger chunks for speed
            if not chunk:
                break
            yield chunk
    
    filename = f"{Path(file.filename).stem}_frames_fast.zip"
    
    return StreamingResponse(
        generate(),
        media_type="application/zip",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )

if __name__ == "__main__":
    import uvicorn
    import sys
    
    # Platform-specific optimizations
    kwargs = {
        "host": "0.0.0.0",
        "port": 8080,
        "workers": 1  # Single worker to avoid overhead
    }
    
    # Only use uvloop and httptools on Unix-like systems
    if sys.platform != "win32":
        kwargs["loop"] = "uvloop"  # Faster event loop (Unix only)
        kwargs["http"] = "httptools"  # Faster HTTP parsing
    
    uvicorn.run(app, **kwargs)
import cv2
import fastapi
from fastapi.responses import FileResponse
import os
import zipfile
import json
import tempfile
from pathlib import Path

app = fastapi.FastAPI()

@app.post("/extract_frames/")
async def extract_frames_zip(
    file: fastapi.UploadFile,
    quality: int = 80   # JPEG quality (1–100)
):
    # Ensure videos directory exists
    os.makedirs("videos", exist_ok=True)
    video_path = f"videos/{file.filename}"
    with open(video_path, "wb") as buffer:
        buffer.write(await file.read())

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise fastapi.HTTPException(status_code=400, detail="Could not open video file")

    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    frame_idx = 0
    extracted_count = 0

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir_path = Path(tmpdir)

        # Extract every frame
        while True:
            ret, frame = cap.read()
            if not ret:
                break

            # Encode and save as JPEG
            _, buffer = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, quality])
            frame_path = tmpdir_path / f"frame_{frame_idx:06d}.jpg"
            with open(frame_path, "wb") as f:
                f.write(buffer.tobytes())

            extracted_count += 1
            frame_idx += 1

        cap.release()

        # Create metadata JSON with timestamps
        metadata = {
            "fps": fps,
            "total_frames": total_frames,
            "extracted_frames": extracted_count,
            "width": width,
            "height": height,
            "frames": [
                {
                    "frame_index": i,
                    "timestamp": i / fps if fps > 0 else 0.0,
                    "filename": f"frame_{i:06d}.jpg"
                }
                for i in range(extracted_count)
            ]
        }
        metadata_path = tmpdir_path / "metadata.json"
        with open(metadata_path, "w") as f:
            json.dump(metadata, f, indent=2)

        # Zip everything
        zip_path = tmpdir_path / "frames.zip"
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zipf:
            for frame_file in sorted(tmpdir_path.glob("frame_*.jpg")):
                zipf.write(frame_file, arcname=frame_file.name)
            zipf.write(metadata_path, arcname="metadata.json")

        # Persist the zip
        final_zip = Path("videos") / f"{Path(file.filename).stem}_frames.zip"

        os.replace(zip_path, final_zip)

    # Cleanup uploaded video
    try:
        os.remove(video_path)
    except:
        pass

    return FileResponse(final_zip, media_type="application/zip", filename=os.path.basename(final_zip))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)

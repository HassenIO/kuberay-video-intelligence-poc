import gradio as gr
import ray
import cv2
import numpy as np
from ultralytics import YOLO
import supervision as sv
from pathlib import Path
import tempfile
import time
import os

# Initialize Ray for local demo (uses available CPUs on your machine)
# For the small 4-CPU cluster spirit we can limit it, but for local wow demo we let it use what you have.
ray.init(ignore_reinit_error=True)

# Small fast model - same as the one deployed on KubeRay
model = YOLO("yolo11n.pt")


@ray.remote
def process_video_chunk(video_path: str, start_frame: int, num_frames: int = 30):
    """Process a chunk of video frames with YOLO + supervision annotation.
    Runs in parallel as a Ray task (great for demonstrating distributed processing).
    """
    cap = cv2.VideoCapture(video_path)
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)

    box_annotator = sv.BoxAnnotator(thickness=2)
    label_annotator = sv.LabelAnnotator(
        text_position=sv.Position.TOP_LEFT, text_thickness=1, text_scale=0.5
    )

    annotated_frames = []
    for _ in range(num_frames):
        ret, frame = cap.read()
        if not ret:
            break
        results = model(frame, verbose=False)[0]
        detections = sv.Detections.from_ultralytics(results)
        annotated = box_annotator.annotate(scene=frame.copy(), detections=detections)
        annotated = label_annotator.annotate(scene=annotated, detections=detections)
        annotated_frames.append(annotated)
    cap.release()
    return annotated_frames


def process_video(video_path, progress=gr.Progress()):
    """Main function called by Gradio.
    Splits video into chunks, processes them in parallel with Ray, then reassembles.
    This gives the big "wow" visual effect even on a modest machine.
    """
    if video_path is None:
        return None, {"error": "Please upload a video first."}

    start_time = time.time()
    progress(0, desc="Analyzing video...")

    cap = cv2.VideoCapture(video_path)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 25
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    cap.release()

    if total_frames == 0:
        return None, {"error": "Could not read video or video is empty."}

    # Split into chunks of ~1 second (30 frames).
    # On small cluster / limited CPU we keep chunks reasonable so we don't overwhelm resources.
    chunk_size = 30
    num_chunks = (total_frames + chunk_size - 1) // chunk_size

    progress(0.1, desc=f"Processing {num_chunks} chunks in parallel with Ray...")

    # Fire off Ray tasks in parallel (this is the distributed part we demonstrate)
    futures = []
    for i in range(num_chunks):
        start_f = i * chunk_size
        futures.append(process_video_chunk.remote(video_path, start_f, chunk_size))

    # Gather results (Ray handles the parallelism)
    all_annotated = []
    for i, fut in enumerate(futures):
        frames = ray.get(fut)
        all_annotated.extend(frames)
        progress(
            0.1 + 0.8 * (i + 1) / num_chunks,
            desc=f"Processed chunk {i + 1}/{num_chunks}",
        )

    # Rebuild video from annotated frames
    progress(0.95, desc="Encoding final annotated video...")
    out_path = tempfile.NamedTemporaryFile(suffix=".mp4", delete=False).name
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(out_path, fourcc, fps, (width, height))
    for frame in all_annotated[:total_frames]:  # safety
        out.write(frame)
    out.release()

    processing_time = time.time() - start_time

    metadata = {
        "original_frames": total_frames,
        "processed_frames": len(all_annotated),
        "fps": round(fps, 2),
        "resolution": f"{width}x{height}",
        "processing_time_seconds": round(processing_time, 2),
        "chunks_used": num_chunks,
        "model": "yolo11n (CPU)",
        "note": "This local demo uses Ray for parallel chunk processing. "
        "The production version runs the same logic via KubeRay RayService on your 4-CPU cluster.",
    }

    progress(1.0, desc="Done!")
    return out_path, metadata


# ====================== Gradio UI ======================
demo = gr.Interface(
    fn=process_video,
    inputs=gr.Video(
        label="Upload short video (10-60s recommended for quick demo)", format="mp4"
    ),
    outputs=[
        gr.Video(label="Annotated video with object detection + tracking"),
        gr.JSON(label="Processing metadata & stats"),
    ],
    title="🎥 Video Intelligence POC - Small Cluster Edition",
    description=(
        "Upload a video and watch YOLOv11n + supervision detect objects in real time (parallelized with Ray).\n\n"
        "**This matches the production deployment on your 4-CPU DigitalOcean cluster** (1 head + 1 worker, 1 CPU per Ray actor).\n"
        "The serve_app.py you deploy with KubeRay exposes /detect-image and /detect-json for real-time API use.\n\n"
        "Tip: Use short clips first. The parallel Ray tasks give you a nice speed-up even on a laptop."
    ),
    examples=[
        # Add example videos if you have them in a /videos folder
    ],
    flagging_mode="never",
    clear_btn="Clear",
    submit_btn="Process Video with Ray + YOLO",
)

if __name__ == "__main__":
    demo.launch(server_name="0.0.0.0", server_port=7860, share=False)

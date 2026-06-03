from ray import serve
from fastapi import FastAPI, UploadFile, File
from fastapi.responses import StreamingResponse, JSONResponse
from ultralytics import YOLO
import supervision as sv
import cv2
import numpy as np
import io

app = FastAPI(
    title="Video Intelligence Service API",
    description="Small-cluster POC (4 CPU total). Object detection + annotation for images/frames. Deployed via KubeRay RayService.",
    version="1.0-small",
)


@serve.deployment(
    num_replicas=1,  # Matches small cluster decision
    ray_actor_options={"num_cpus": 1.0},  # 1 CPU per replica - fits 4 CPU cluster
    max_ongoing_requests=8,
)
class VideoDetector:
    """Handles YOLO inference and annotation on a single frame. CPU-only, small model for low-resource cluster."""

    def __init__(self):
        # yolo11n = nano model, very fast on CPU, good enough for POC
        self.model = YOLO("yolo11n.pt")
        self.box_annotator = sv.BoxAnnotator(thickness=2)
        self.label_annotator = sv.LabelAnnotator(
            text_position=sv.Position.TOP_LEFT, text_thickness=1, text_scale=0.5
        )

    def detect_and_annotate(self, frame: np.ndarray) -> np.ndarray:
        """Run detection and return annotated frame (for visual demo)."""
        results = self.model(frame, verbose=False)[0]
        detections = sv.Detections.from_ultralytics(results)
        annotated = self.box_annotator.annotate(
            scene=frame.copy(), detections=detections
        )
        annotated = self.label_annotator.annotate(
            scene=annotated, detections=detections
        )
        return annotated

    def detect_json(self, frame: np.ndarray) -> dict:
        """Return structured detection data (for API / analytics)."""
        results = self.model(frame, verbose=False)[0]
        detections = sv.Detections.from_ultralytics(results)
        return {
            "num_detections": len(detections),
            "class_ids": detections.class_id.tolist()
            if detections.class_id is not None
            else [],
            "class_names": [self.model.names[i] for i in detections.class_id]
            if detections.class_id is not None
            else [],
            "confidences": detections.confidence.tolist()
            if detections.confidence is not None
            else [],
            "boxes_xyxy": detections.xyxy.tolist()
            if detections.xyxy is not None
            else [],
            "model": "yolo11n",
            "device": "cpu",
        }


@serve.deployment(num_replicas=1)
@serve.ingress(app)
class VideoService:
    """FastAPI ingress that exposes /detect-image and /detect-json endpoints.
    All heavy lifting delegated to VideoDetector actor (1 CPU).
    """

    def __init__(self, detector: VideoDetector):
        self.detector = detector

    @app.post(
        "/detect-image",
        summary="Upload image/frame → return annotated JPG",
        response_class=StreamingResponse,
    )
    async def detect_image(self, file: UploadFile = File(...)):
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if frame is None:
            return JSONResponse(
                {"error": "Could not decode image. Send valid JPG/PNG."},
                status_code=400,
            )

        # Call the detector (runs on the Ray actor with 1 CPU)
        annotated = await self.detector.detect_and_annotate.remote(frame)

        _, img_encoded = cv2.imencode(".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, 85])
        return StreamingResponse(
            io.BytesIO(img_encoded.tobytes()),
            media_type="image/jpeg",
            headers={"Content-Disposition": "inline; filename=annotated.jpg"},
        )

    @app.post(
        "/detect-json",
        summary="Upload image/frame → return detection metadata as JSON",
        response_class=JSONResponse,
    )
    async def detect_json(self, file: UploadFile = File(...)):
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if frame is None:
            return JSONResponse({"error": "Could not decode image"}, status_code=400)

        result = await self.detector.detect_json.remote(frame)
        return result

    @app.get("/health")
    async def health(self):
        return {
            "status": "healthy",
            "model": "yolo11n.pt (CPU)",
            "resources": "1 CPU per replica, 1 replica total (small cluster optimized)",
            "endpoints": ["/detect-image", "/detect-json"],
        }


video_detector = VideoDetector.bind()
video_service = VideoService.bind(video_detector)

# To run locally: `RAY_SERVE_HTTP_HOST=0.0.0.0 RAY_SERVE_HTTP_PORT=8000 serve run serve_app:video_service`
# then test with: curl -F "file=@test.jpg" http://localhost:8000/detect-image --output annotated.jpg

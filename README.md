# Video Intelligence POC

End-to-end demo of a video annotation application using Ray Serve (for the API), Gradio (for the local UX), and KubeRay + Terraform (for Kubernetes deployment).

## Phase 1 – Local development

### Prerequisites

- Python 3.13+
- [uv](https://docs.astral.sh/uv/) (recommended) or `pip`/`venv`
- System packages required by OpenCV/FFmpeg (macOS: `brew install ffmpeg`)
- `curl`, `jq` (optional but nice for pretty output)

### Install dependencies

```bash
uv sync
```

### Sanity-check Ray

```bash
make ray-check
# -> prints dashboard URL, address, and available resources
```

### Start the Ray Serve API

```bash
make local-serve
# equivalent: RAY_SERVE_HTTP_HOST=0.0.0.0 RAY_SERVE_HTTP_PORT=8000 uv run serve run serve_app:video_service
```

Run this in its own terminal. The first launch downloads the `yolo11n.pt` weights to your Ultralytics cache (~7 MB). Stop it with `Ctrl+C` when finished.

### Prepare a sample frame

Use the bundled `demo.mp4` to generate a still image for smoke tests:

```bash
uv run python scripts/extract_frame.py demo.mp4 --frame-index 0 --output /tmp/frame.jpg
```

### Hit the API endpoints

```bash
make local-serve-test IMAGE=/tmp/frame.jpg
# Optional: SERVE_URL=http://127.0.0.1:8000 make local-serve-test IMAGE=/tmp/frame.jpg
```

This script calls `/health`, `/detect-json`, and `/detect-image`, saving the annotated JPEG to a temp file.

### Run the Gradio demo UI

```bash
make local-ui
# opens http://127.0.0.1:7860
```

Upload a short clip (10–60 seconds). The Ray tasks chunk the video (30 frames per shard), annotate each frame in parallel, then rebuild an MP4 and metadata JSON.

### Troubleshooting

- **Ultralytics weight download fails** – ensure outbound internet; delete `~/.cache/ultralytics` if the file is corrupted and retry.
- **`ray.init` OOM / object store errors** – close stray Ray clusters (`make ray-stop`) and rerun `make ray-check`.
- **OpenCV codec errors** – install FFmpeg (`brew install ffmpeg` on macOS) so `cv2.VideoWriter` can emit MP4.
- **Serve endpoint 500s** – tail logs in the Serve terminal, look for `ModuleNotFoundError` or CUDA warnings (model is CPU-only; ignore GPU notices).
- **Gradio page blank** – ensure `demo.mp4` or uploaded video is valid; watch terminal for `Could not read video or video is empty`.

## Phase 2 – Kubernetes (DigitalOcean + KubeRay)

### 1. Provision infrastructure

1. Copy the token template: `cp terraform/secrets.auto.tfvars.example terraform/secrets.auto.tfvars` and add your DigitalOcean API token.
2. Run the automated bootstrap (Terraform + operator install + RayService apply):

   ```bash
   make setup
   ```

   The script performs `terraform init/plan/apply`, saves the kubeconfig via `doctl`, installs the KubeRay operator, creates the namespace, copies `serve_app.py` into `k8s/`, forces the `video-intelligence-app` ConfigMap to regenerate in `ray-system`, and applies the manifests via `kubectl apply -k`.

3. To tear everything down (Terraform destroy + kube context cleanup):

   ```bash
   make teardown
   ```

### 2. Inspect cluster state

```bash
make k8s-status           # pods, services, RayService status
kubectl logs -n ray-system -l ray.io/node-type=head   # optional deeper dive
```

### 3. Port-forward Serve + dashboard

```bash
make k8s-port-forward
# -> exposes http://127.0.0.1:8000 (Serve) and http://127.0.0.1:8265 (Ray dashboard)
```

Leave this command running in its own terminal; `Ctrl+C` stops the forwards.

### 4. Smoke-test the remote API

Reuse the local sample frame (or any image) and run:

```bash
make k8s-test IMAGE=/tmp/frame.jpg   # automatically port-forwards, curls /health, /detect-json, /detect-image
```

Once the test completes, the port-forward stops automatically.

> Detailed background on the manifests, debugging commands, and scaling guidance lives in `docs/PLAN.md` and `k8s/README.md`.

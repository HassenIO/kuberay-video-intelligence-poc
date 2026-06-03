## Repository Structure

- `app.py` – Gradio UI that runs Ray tasks locally to process uploaded videos chunk-by-chunk with YOLOv11n + Supervision overlays.
- `serve_app.py` – Ray Serve FastAPI ingress exposing `/detect-image`, `/detect-json`, `/health`; bound as `serve_app:video_service` for both local Serve runs and KubeRay deployments.
- `demo.mp4` – Sample clip for exercising `app.py` without sourcing your own media.
- `pyproject.toml` / `uv.lock` – Python project metadata and dependency lock (Ray, Ultralytics, Gradio, Supervision, OpenCV, etc.).
- `Makefile` – Placeholder for future automation (currently empty but reserved for commands mentioned in docs).
- `scripts/` – Shell helpers:
  - `setup.sh` provisions DigitalOcean Kubernetes via Terraform, installs KubeRay operator, applies RayService manifest, waits for readiness.
  - `teardown.sh` destroys Terraform-managed resources and clears kube context.
- `terraform/` – Infrastructure as code: DigitalOcean cluster definition (`main.tf`), provider config, variables, outputs, tfstate artifacts, and `secrets.auto.tfvars[.example]` for API tokens.
- `k8s/` – KubeRay manifests:
  - `kustomization.yaml` generates `video-intelligence-app` ConfigMap from `serve_app.py` and applies `rayservice-cpu.yaml`.
  - `rayservice-cpu.yaml` defines the RayService CRD (head + worker specs, ConfigMap mount, Serve deployments).
  - `README.md` explains deployment steps, debugging commands, and troubleshooting notes.
- `docs/PLAN.md` – Two-phase implementation checklist (local run vs. online/Kubernetes run).
- `docs/STRUCTURE.md` – *this file* describing project layout.

## Runtime Flow

1. **Local demo (`app.py`)**
   - User uploads video → Ray tasks (`process_video_chunk`) annotate frame batches → Gradio outputs annotated MP4 plus metadata JSON.
2. **Serve API (`serve_app.py`)**
   - YOLO model + Supervision annotators initialized once per Ray actor.
   - FastAPI endpoints call Ray actor methods for JPEG annotation or JSON detections.
3. **Kubernetes deployment**
   - `scripts/setup.sh` → Terraform cluster → Helm installs KubeRay operator → ConfigMap sync → `kubectl apply -k k8s` starts RayService.
   - Serve endpoints exposed via RayService-managed Kubernetes Services for port-forward or ingress.

## Supporting Assets

- `README.md` – High-level project description.
- `demo.mp4` – Quick testing media for Gradio flow.
- `.terraform` outputs (`terraform.tfstate`, `tfplan`, etc.) – Track cloud resources (do not commit sensitive files).

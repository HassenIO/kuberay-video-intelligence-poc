# Testing Guide

This project currently relies on manual verification. Below are the steps I performed (or prepared) while validating Phase 1, plus the recommended flow for Phase 2 once cloud credentials are available.

## Phase 1 – Local Workstation

1. **Dependency install** – `uv sync` (ensures Ray, Ultralytics, Supervision, Gradio, OpenCV, NumPy are present).
2. **Ray sanity check** – `make ray-check` (invokes `scripts/ray_check.py`, prints dashboard URL/resource summary, confirms `ray.init()` works).
3. **Serve API smoke test**
   - Start the service: `make local-serve` (leave running).
   - Extract a sample frame: `uv run python scripts/extract_frame.py demo.mp4 --output /tmp/frame.jpg`.
   - Hit endpoints: `make local-serve-test IMAGE=/tmp/frame.jpg` (calls `/health`, `/detect-json`, `/detect-image`, saves annotated JPEG to a temp file).
4. **Gradio UI** – `make local-ui`, open `http://127.0.0.1:7860`, upload `demo.mp4`, confirm annotated video + metadata JSON render correctly. Stop the app with `Ctrl+C`.
5. **Cleanup** – `make ray-stop` (only if Ray keeps running in the background).

## Phase 2 – Kubernetes (DigitalOcean + KubeRay)

> Not executed here because it provisions billable infrastructure. Follow these steps in your cloud environment.

1. **Terraform bootstrap** – Copy `terraform/secrets.auto.tfvars.example` → `terraform/secrets.auto.tfvars`, add `do_token`, then run `make setup` (Terraform apply → `doctl` kubeconfig → KubeRay operator install → copy `serve_app.py` into `k8s/` → `kubectl apply -k k8s`).
2. **Cluster status** – `make k8s-status` to list pods, services, and RayService status (optionally inspect logs via `kubectl logs -n ray-system -l ray.io/node-type=head`).
3. **Port-forwarding** – `make k8s-port-forward` (Serve → `http://127.0.0.1:8000`, dashboard → `http://127.0.0.1:8265`). Keep this running for manual testing.
4. **Remote smoke test** – `make k8s-test IMAGE=/tmp/frame.jpg` (temporarily port-forwards the Serve service, executes the same curl checks as Phase 1, then tears down the tunnel).
5. **Teardown** – `make teardown` when finished to destroy the DigitalOcean cluster and clean kube contexts.

Keep this document in sync with future automation (e.g., CI workflows, container builds) so contributors know how to exercise both local and cloud paths.

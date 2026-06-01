Kubernetes configuration for the Video Intelligence RayService

# What it is?

This folder contains rthe Kubernetes manifest (`rayservice-cpu.yaml`) that deploys a Ray cluster using the RayService CRD (KubeRay).

The manifest provisions a Ray head and one worker group, mounts the Serve application via a `ConfigMap`, and exposes Serve and dashboard services.

We need it to run Ray (and Ray Serve) on Kubernetes to host the video-intelligence service with predictable lifecycle, scaling, and observability. Using RayService simplifies cluster lifecycle (create/delete/upgrade) and allows deploying Ray Serve applications alongside the cluster.

# How it works

At a high level, the manifest:

- `RayService` CR creates a RayCluster. The operator creates head and worker pods and the related Services.
- `serveConfigV2` in the manifest instructs the operator to deploy a Ray Serve application after the cluster is ready. It references `import_path: serve_app:video_service`.
- A `ConfigMap` (created in the same manifest) contains the `serve_app.py` source and is mounted into the Ray pods at `/home/ray/serve_app.py` so the Serve runtime can import it.
- The containers set `PYTHONPATH=/home/ray:$PYTHONPATH` so `/home/ray` is discoverable for imports.
- Shared memory for object store is provided by an `emptyDir` volume mounted at `/dev/shm` (medium: Memory) to avoid issues with small default `/dev/shm` sizes in some runtimes.
- Health checks use `ray health-check` (exec probes) that query the cluster head via GCS or local raylet health endpoints. Probes are tuned with reasonable delays to avoid false failures during startup.

For this, the `k8s/rayservice-cpu.yaml` is the main manifest (includes ConfigMap + RayService) which uses `serve_app.py` which is the Serve application (also present in the repo root.

> ConfigMap is authoritative at runtime.

The manifest creates a ConfigMap `video-intelligence-app` which contains `serve_app.py`, a RayService `video-intelligence-service` which is the KubeRay CRD that manages the RayCluster and Serve application. And finally Services (head, serve) which is the ClusterIP services for dashboard, GCS, serve endpoints.

# How to deploy

Follow:

1. Ensure the `ray-system` namespace exists (the manifest uses this namespace):

```bash
kubectl create namespace ray-system || true
```

2. Apply the manifest:

```bash
kubectl apply -f k8s/rayservice-cpu.yaml -n ray-system
```

3. Watch pods until healthy:

```bash
kubectl get pods -n ray-system -o wide
kubectl get rayservice video-intelligence-service -n ray-system
```

How to test the deployment
- Check cluster and pod status:

```bash
kubectl get pods -n ray-system
kubectl describe pod <pod-name> -n ray-system
kubectl logs <pod-name> -n ray-system -c ray-head
kubectl logs <pod-name> -n ray-system -c ray-worker
```

- Check RayService application status (shows Serve deployment statuses):

```bash
kubectl get rayservice video-intelligence-service -n ray-system -o yaml
# Look for `applicationStatuses` and `serveDeploymentStatuses` entries
```

- Access Serve endpoints locally via port-forwarding (example):

```bash
# Forward Serve service (serve-svc name printed by the operator, for example: video-intelligence-service-<id>-serve-svc)
kubectl get svc -n ray-system | grep video-intelligence
kubectl port-forward svc/<serve-svc-name> 8000:8000 -n ray-system
# then from your workstation
curl -s http://127.0.0.1:8000/
```

- Access the Ray dashboard:

```bash
kubectl port-forward svc/<head-svc-name> 8265:8265 -n ray-system
# then open http://127.0.0.1:8265
```

# Troubleshooting

During my iterations, I got the following issues which I troubleshooted:

## Pod CrashLoopBackOff or Exit Code 137 (OOM):

- Check `kubectl logs <pod> -c <container>` and `kubectl describe pod` events.
- Increase `resources.requests`/`limits` in `rayservice-cpu.yaml` for the head or workers.

## Readiness/Liveness probe failures (HTTP 404 or timeouts):

- Ray 2.x may not expose the old HTTP probe endpoints used previously; this manifest uses `ray health-check` exec probes.
- If you see HTTP 404 on `/api/ray/health`, adjust probes to use `exec` or point to the correct endpoints for your Ray version.

## Serve application not found (`ModuleNotFoundError: No module named 'serve_app'`):

- Confirm `ConfigMap` mount exists and the file is at `/home/ray/serve_app.py` inside the head pod:

```bash
kubectl exec -n ray-system <head-pod> -c ray-head -- ls -la /home/ray/serve_app.py
```

- Confirm the container has `PYTHONPATH` including `/home/ray`: inspect `env` or `kubectl describe pod`.
- Health-check timeouts on worker init: the init container `wait-gcs-ready` waits for the head GCS to be reachable. If it times out, check head service and DNS:

```bash
kubectl get svc -n ray-system
kubectl exec -n ray-system <worker-pod> -- ping -c 3 <head-svc-name>.ray-system.svc.cluster.local
```

# Debugging

Here are the following commands I find useful:

```bash
kubectl get pods -n ray-system -o wide
kubectl describe pod <pod-name> -n ray-system
kubectl logs <pod-name> -n ray-system --all-containers
kubectl get events -n ray-system --sort-by='.lastTimestamp' | tail -40
kubectl get rayservice video-intelligence-service -n ray-system -o yaml
```

# Production notes/TODO

For production, first remove fractional CPU usage, increase memory, and tune `num_replicas` and `ray_actor_options`.

Consider storing application code in an image or Git-backed artifact store instead of a ConfigMap for larger codebases (MLOps practice).

Finally monitor `/dev/shm` usage and set `emptyDir.medium: Memory` size appropriately for object store performance.

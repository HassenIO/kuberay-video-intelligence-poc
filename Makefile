UV ?= uv
SERVE_HOST ?= 0.0.0.0
SERVE_PORT ?= 8000
SERVE_URL ?= http://127.0.0.1:8000

setup:
	./scripts/setup.sh

teardown:
	./scripts/teardown.sh

ray-check:
	$(UV) run python scripts/ray_check.py

local-serve:
	RAY_SERVE_HTTP_HOST=$(SERVE_HOST) RAY_SERVE_HTTP_PORT=$(SERVE_PORT) $(UV) run serve run serve_app:video_service

local-serve-test:
	@if [ -z "$(IMAGE)" ]; then echo "IMAGE=<path/to/frame.jpg> is required" >&2; exit 1; fi
	SERVE_URL=$(SERVE_URL) ./scripts/test_serve.sh "$(IMAGE)"

local-ui:
	$(UV) run python app.py

ray-stop:
	$(UV) run ray stop || true

k8s-apply:
	cp serve_app.py k8s/serve_app.py
	kubectl delete configmap video-intelligence-app -n ray-system --ignore-not-found || true
	kubectl apply -k k8s

k8s-status:
	./scripts/k8s_status.sh

k8s-port-forward:
	./scripts/k8s_port_forward.sh

k8s-test:
	@if [ -z "$(IMAGE)" ]; then echo "IMAGE=<path/to/frame.jpg> is required" >&2; exit 1; fi
	./scripts/k8s_test_remote.sh "$(IMAGE)"

.PHONY: setup teardown ray-check local-serve local-serve-test local-ui ray-stop k8s-apply k8s-status k8s-port-forward k8s-test

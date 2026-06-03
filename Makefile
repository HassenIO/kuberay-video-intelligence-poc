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

.PHONY: setup teardown ray-check local-serve local-serve-test local-ui ray-stop

data "digitalocean_kubernetes_versions" "current" {}

resource "digitalocean_kubernetes_cluster" "video_poc" {
  name    = "kuberay-video-poc"
  region  = "lon1"
  version = data.digitalocean_kubernetes_versions.current.latest_version

  node_pool {
    name       = "cpu-workers"
    size       = "c-4" # CPU-intensive, enough for Ray/YOLO on CPU
    node_count = 2
    auto_scale = true
    min_nodes  = 1
    max_nodes  = 4

    tags = ["kuberay", "video-intelligence", "mlops-poc"]
  }
}

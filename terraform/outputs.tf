output "kubeconfig" {
  value     = digitalocean_kubernetes_cluster.video_poc.kube_config[0].raw_config
  sensitive = true
}

output "cluster_name" {
  value = digitalocean_kubernetes_cluster.video_poc.name
}

output "cluster_endpoint" {
  value = digitalocean_kubernetes_cluster.video_poc.endpoint
}

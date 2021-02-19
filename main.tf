locals {
  external_dns_docker_image = "k8s.gcr.io/external-dns/external-dns:v${var.external_dns_version}"
  external_dns_version      = var.external_dns_version
}


resource "kubernetes_service_account" "this" {
  automount_service_account_token = true
  metadata {
    name      = "external-dns"
    namespace = var.k8s_namespace
    labels = {
      "app.kubernetes.io/name"       = "external-dns"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_cluster_role" "this" {
  metadata {
    name = "external-dns"

    labels = {
      "app.kubernetes.io/name"       = "external-dns"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  rule {
    api_groups = [
      "",
    ]

    resources = [
      "services",
      "endpoints",
      "pods"
    ]

    verbs = [
      "get",
      "list",
      "watch",
    ]
  }

  rule {
    api_groups = [
      "",
    ]

    resources = [
      "services",
    ]

    verbs = [
      "get",
      "list",
      "watch",
    ]
  }

  rule {
    api_groups = [
      "",
    ]

    resources = [
      "pods",
    ]

    verbs = [
      "get",
      "list",
      "watch",
    ]
  }
  rule {
    api_groups = [
      "extensions",
      "networking.k8s.io"
    ]

    resources = [
      "ingresses",
    ]

    verbs = [
      "get",
      "watch",
      "list",
    ]
  }
  rule {
    api_groups = [
      "",
    ]

    resources = [
      "nodes",
    ]

    verbs = [
      "list",
      "watch",
    ]
  }
  rule {
    api_groups = [
      "networking.istio.io",
    ]

    resources = [
      "gateways", 
      "virtualservices",
    ]

    verbs = [
      "get",
      "list",
      "watch",
    ]
  }
}

resource "kubernetes_cluster_role_binding" "this" {
  metadata {
    name = "external-dns-viewer"

    labels = {
      "app.kubernetes.io/name"       = "external-dns"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.this.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.this.metadata[0].name
    namespace = kubernetes_service_account.this.metadata[0].namespace
  }
}

resource "kubernetes_deployment" "this" {
  depends_on = [kubernetes_cluster_role_binding.this]

  metadata {
    name      = "external-dns"
    namespace = var.k8s_namespace

    labels = {
      "app.kubernetes.io/name"       = "external-dns"
      "app.kubernetes.io/version"    = "v${local.external_dns_version}"
      "app.kubernetes.io/managed-by" = "terraform"
    }

    annotations = {
      "field.cattle.io/description" = "AWS External DNS"
    }
  }
  
  spec {

    replicas = var.k8s_replicas

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "external-dns"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = merge(
          {
            "app.kubernetes.io/name"    = "external-dns"
            "app.kubernetes.io/version" = local.external_dns_version
          },
          var.k8s_pod_labels
        )
      }

      spec {
        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["external-dns"]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }

        automount_service_account_token = true

        dns_policy = "ClusterFirst"

        restart_policy = "Always"

        container {
          name                     = "server"
          image                    = local.external_dns_docker_image
          image_pull_policy        = "Always"
          termination_message_path = "/dev/termination-log"

          args = [
            "--source=service",
            "--source=ingress",
            "--source=istio-gateway",
            "--source=istio-virtualservice",
            "--domain-filter=${var.domain}",
            "--provider=aws",
            "--policy=upsert-only",
            "--aws-zone-type=${var.aws_zone_type}",
            "--registry=txt",
            "--txt-owner-id=${var.hosted_zone_id}",
          ]
        }
        security_context {
          fs_group = 65534
        }

        service_account_name             = kubernetes_service_account.this.metadata[0].name
        termination_grace_period_seconds = 60
      }
    }
  }
}

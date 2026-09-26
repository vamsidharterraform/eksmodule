locals {
  common_tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
    Terraform   = "true"

    "karpenter.sh/discovery" = var.cluster_name
  }
}
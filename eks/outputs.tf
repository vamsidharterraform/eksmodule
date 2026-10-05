output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_version" {
  description = "EKS cluster version"
  value       = aws_eks_cluster.main.version
}

output "cluster_nodegroup_version" {
  description = "EKS node group Kubernetes versions"

  value = {
    for name, nodegroup in aws_eks_node_group.main :
    name => nodegroup.version
  }
}

output "oidc_provider_arn" {
  description = "OIDC Provider ARN"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC Provider URL"
  value       = aws_iam_openid_connect_provider.eks.url
}

output "node_group_names" {
  description = "EKS Node Group Names"
  value       = keys(var.node_groups)
}

output "node_role_arn" {
  description = "Worker Node IAM Role ARN"
  value       = aws_iam_role.node.arn
}

output "external_secrets_role_arn" {
  description = "External Secrets Operator IRSA role ARN"
  value       = aws_iam_role.external_secrets.arn
}

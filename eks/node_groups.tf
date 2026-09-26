resource "aws_eks_node_group" "main" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key

  node_role_arn = aws_iam_role.node.arn
  subnet_ids    = var.subnet_ids

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type

  labels = {
    workload = each.key
    managed  = "terraform"
    project  = "employee-portal"
  }

  dynamic "taint" {
    for_each = each.key == "system" ? [1] : []

    content {
      key    = "workload"
      value  = "system"
      effect = "NO_SCHEDULE"
    }
  }

  scaling_config {
    desired_size = each.value.scaling_config.desired_size
    max_size     = each.value.scaling_config.max_size
    min_size     = each.value.scaling_config.min_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(
    local.common_tags,
    {
      NodeGroup = each.key
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_policy
  ]
}
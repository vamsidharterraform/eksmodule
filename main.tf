locals {
  common_tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
    Terraform   = "true"

    "karpenter.sh/discovery" = var.cluster_name
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

############################################
# EKS Cluster IAM Role
############################################

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_access_entry" "terraform_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::942548380800:user/terraform"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "terraform_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::942548380800:user/terraform"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.terraform_admin
  ]
}

############################################
# Existing GitLab IAM Role
############################################

data "aws_iam_role" "gitlab_deploy" {
  name = "gitlab-eks-deploy-role"
}

############################################
# GitLab CI/CD → EKS API Access
############################################

resource "aws_iam_policy" "gitlab_eks_api_access" {
  name        = "gitlab-eks-api-access"
  description = "Allow GitLab CI/CD to access EKS cluster"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "eks:DescribeCluster"
        ]

        Resource = aws_eks_cluster.main.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "gitlab_eks_api_access" {
  role       = data.aws_iam_role.gitlab_deploy.name
  policy_arn = aws_iam_policy.gitlab_eks_api_access.arn
}
############################################
# GitLab CI/CD → EKS Access
############################################

resource "aws_eks_access_entry" "gitlab_deploy" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_iam_role.gitlab_deploy.arn
  type          = "STANDARD"

  depends_on = [
    aws_eks_cluster.main
  ]
}

resource "aws_eks_access_policy_association" "gitlab_deploy" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_iam_role.gitlab_deploy.arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.gitlab_deploy
  ]
}

############################################
# EKS Cluster
############################################

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator"
  ]

  tags = merge(
    local.common_tags,
    {
      Name = var.cluster_name
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}

############################################
# OIDC Provider (IRSA Support)
############################################

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    data.tls_certificate.eks.certificates[0].sha1_fingerprint
  ]

  tags = local.common_tags
}

############################################
# Worker Node IAM Role
############################################

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "node_policy" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}


############################################
# Amazon CloudWatch Observability Add-on
############################################

############################################
# Amazon CloudWatch Observability Add-on
############################################

resource "aws_eks_addon" "cloudwatch_observability" {

  cluster_name = aws_eks_cluster.main.name

  addon_name = "amazon-cloudwatch-observability"

  configuration_values = jsonencode({
    otelContainerInsights = {
      enabled = true
    }

    containerLogs = {
      enabled = true
    }
  })

  pod_identity_association {
    service_account = "cloudwatch-agent"
    role_arn        = aws_iam_role.cloudwatch_observability.arn
  }

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.cloudwatch_observability
  ]
}
############################################
# Managed Node Groups
############################################

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

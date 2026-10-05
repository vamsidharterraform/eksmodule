############################################
# EBS CSI Driver IAM Role
############################################

resource "aws_iam_role" "ebs_csi" {

  name = "${var.cluster_name}-ebs-csi-role"

  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {

        Effect = "Allow"

        Principal = {

          Federated = aws_iam_openid_connect_provider.eks.arn

        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {

          StringEquals = {

            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"

          }

        }

      }

    ]

  })

  tags = local.common_tags
}

############################################
# EBS CSI Driver Policy
############################################

resource "aws_iam_role_policy_attachment" "ebs_csi" {

  role = aws_iam_role.ebs_csi.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"

}

############################################
# AWS EBS CSI Driver Add-on
############################################

resource "aws_eks_addon" "ebs_csi" {

  cluster_name = aws_eks_cluster.main.name

  addon_name = "aws-ebs-csi-driver"

  service_account_role_arn = aws_iam_role.ebs_csi.arn

  depends_on = [

    aws_iam_role_policy_attachment.ebs_csi

  ]

}

############################################
# CloudWatch Observability IAM Role
############################################

resource "aws_iam_role" "cloudwatch_observability" {
  name = "${var.cluster_name}-cloudwatch-observability-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "pods.eks.amazonaws.com"
        }

        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = local.common_tags
}

############################################
# CloudWatch Agent IAM Policy
############################################

resource "aws_iam_role_policy_attachment" "cloudwatch_observability" {
  role       = aws_iam_role.cloudwatch_observability.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

############################################
# EKS Pod Identity Agent
############################################

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [
    aws_eks_cluster.main
  ]
}

############################################
# AWS VPC CNI Add-on
# NetworkPolicy Enforcement
############################################

resource "aws_eks_addon" "vpc_cni" {

  cluster_name = aws_eks_cluster.main.name

  addon_name = "vpc-cni"
  addon_version = "v1.23.0-eksbuild.1"

  configuration_values = jsonencode({
    enableNetworkPolicy = "true"

    env = {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
  })

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.node_policy
  ]
}
############################################
# External Secrets Operator IRSA
############################################

data "aws_iam_policy_document" "external_secrets_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.cluster_name}-external-secrets-role"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "external_secrets" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:dev/eks/myapp-*"
    ]
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  name   = "${var.cluster_name}-external-secrets"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets.json
}


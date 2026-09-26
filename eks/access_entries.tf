############################################
# Terraform Admin → EKS
############################################

resource "aws_eks_access_entry" "terraform_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::942548380800:user/terraform"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "terraform_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::942548380800:user/terraform"

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

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
# GitLab → EKS API Permission
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
# GitLab → EKS Access Entry
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
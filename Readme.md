# EKS Terraform Module

This Terraform module provisions and configures an Amazon EKS cluster, including IAM roles, EKS access entries, OIDC integration, managed node groups, and EKS add-ons.

## Architecture

```text
                    AWS VPC
                       |
                       v
                  Amazon EKS
                       |
        +--------------+--------------+
        |              |              |
        v              v              v
   Control Plane   System Nodes   Application Nodes
                       |
                       v
                 Kubernetes Pods
```

## Module Responsibilities

The EKS module manages the following:

- Amazon EKS cluster
- EKS cluster IAM role
- Worker node IAM role
- EKS managed node groups
- EKS access entries
- EKS access policy associations
- IAM OIDC provider
- EKS add-ons
- EKS cluster control-plane logging
- Common EKS resource tagging

## Module Structure

```text
eks/
│
├── main.tf
├── locals.tf
├── iam.tf
├── access_entries.tf
├── oidc.tf
├── node_groups.tf
├── addons.tf
├── variables.tf
├── outputs.tf
└── README.md
```

## File Responsibilities

| File | Responsibility |
|---|---|
| `main.tf` | Creates the EKS cluster |
| `locals.tf` | Defines common tags and reusable local values |
| `iam.tf` | Creates EKS cluster and worker node IAM roles |
| `access_entries.tf` | Configures EKS API access for IAM principals |
| `oidc.tf` | Creates the EKS IAM OIDC provider |
| `node_groups.tf` | Creates EKS managed node groups |
| `addons.tf` | Configures EKS managed add-ons |
| `variables.tf` | Defines module input variables |
| `outputs.tf` | Exposes EKS cluster outputs |

## Resources Created

### EKS Cluster

The module creates an Amazon EKS cluster with:

- Configurable Kubernetes version
- Private endpoint access
- Public endpoint access
- API and ConfigMap authentication mode
- Control-plane logging
- VPC subnet integration

Example:

```hcl
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn
}
```

## IAM Roles

The module creates EKS-specific IAM roles.

### EKS Cluster IAM Role

Used by the EKS control plane to interact with AWS services.

```text
EKS Control Plane
       |
       v
Cluster IAM Role
       |
       v
AmazonEKSClusterPolicy
```

### Worker Node IAM Role

Used by EC2 worker nodes in the managed node groups.

The role has permissions including:

- `AmazonEKSWorkerNodePolicy`
- `AmazonEKS_CNI_Policy`
- `AmazonEC2ContainerRegistryReadOnly`

```text
EKS Managed Node Group
          |
          v
      EC2 Nodes
          |
          v
    Worker Node Role
```

## EKS Access Entries

The module uses the EKS API-based access mechanism to authorize IAM principals to access the Kubernetes API.

Current access entries include:

### Terraform Administrator

```text
Terraform IAM User
       |
       v
EKS Access Entry
       |
       v
AmazonEKSClusterAdminPolicy
```

### GitLab CI/CD

```text
GitLab CI/CD
       |
       v
GitLab IAM Role
       |
       v
EKS Access Entry
       |
       v
AmazonEKSClusterAdminPolicy
```

Access is configured at cluster scope.

The cluster uses:

```hcl
authentication_mode = "API_AND_CONFIG_MAP"
```

This allows EKS API access entries to be used along with the Kubernetes `aws-auth` ConfigMap mechanism where required.

## OIDC Provider

The module creates an IAM OIDC provider for the EKS cluster.

```text
EKS Cluster
     |
     v
OIDC Provider
     |
     v
IAM Web Identity Federation
     |
     v
AWS IAM Roles
```

This enables Kubernetes workloads to obtain AWS permissions without storing long-lived AWS access keys inside pods.

The OIDC provider can be used for IAM Roles for Service Accounts (IRSA).

## Managed Node Groups

The module supports multiple managed node groups using `for_each`.

Example:

```text
EKS Cluster
│
├── System Node Group
│   └── System workloads
│
└── Application Node Group
    └── Application workloads
```

Node group configuration can include:

- Instance types
- Capacity type
- Desired size
- Minimum size
- Maximum size
- Kubernetes labels
- Kubernetes taints
- Update configuration

The system node group can use a taint to ensure that only appropriate workloads are scheduled onto it.

## EKS Add-ons

The EKS module can manage AWS-supported EKS add-ons such as:

```text
EKS Cluster
│
├── VPC CNI
├── EBS CSI Driver
├── EKS Pod Identity Agent
└── CloudWatch Observability
```

### VPC CNI

Provides networking for Kubernetes pods using AWS VPC networking.

It can also be configured for:

- NetworkPolicy enforcement
- Prefix delegation
- Additional pod IP capacity

### EBS CSI Driver

Allows Kubernetes workloads to dynamically provision and attach Amazon EBS volumes.

```text
Pod
 |
 v
PVC
 |
 v
EBS CSI Driver
 |
 v
Amazon EBS
```

### EKS Pod Identity Agent

Allows Kubernetes workloads to obtain AWS IAM credentials without embedding AWS access keys in containers.

```text
Pod
 |
 v
Pod Identity Agent
 |
 v
IAM Role
 |
 v
AWS Service
```

### CloudWatch Observability

Collects Kubernetes and application telemetry and sends logs and metrics to Amazon CloudWatch.

```text
Pods / Nodes
     |
     v
CloudWatch Observability
     |
     v
CloudWatch
```

## Cluster Logging

The module enables EKS control-plane logs such as:

- API server logs
- Audit logs
- Authenticator logs

These logs can be delivered to Amazon CloudWatch for monitoring and troubleshooting.

## Variables

Typical inputs include:

| Variable | Description | Type |
|---|---|---|
| `cluster_name` | EKS cluster name | `string` |
| `cluster_version` | Kubernetes version | `string` |
| `subnet_ids` | Subnets used by EKS | `list(string)` |
| `node_groups` | Managed node group configuration | `map(object)` |
| `environment` | Environment name | `string` |

## Example Module Usage

From the root Terraform configuration:

```hcl
module "eks" {
  source = "./modules/eks"

  cluster_name    = "prod-app-cluster"
  cluster_version = "1.33"

  subnet_ids = module.vpc.private_subnet_ids

  environment = "dev"

  node_groups = {
    system = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      scaling_config = {
        desired_size = 2
        min_size     = 2
        max_size     = 3
      }
    }

    application = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      scaling_config = {
        desired_size = 2
        min_size     = 2
        max_size     = 4
      }
    }
  }
}
```

## Outputs

The module can expose values such as:

```text
EKS cluster name
EKS cluster ARN
EKS cluster endpoint
EKS cluster CA certificate
EKS OIDC issuer URL
Node group information
```

These outputs can be consumed by other Terraform modules or the root configuration.

## Deployment

Initialize Terraform:

```bash
terraform init
```

Validate the configuration:

```bash
terraform validate
```

Review the changes:

```bash
terraform plan
```

Apply the EKS infrastructure:

```bash
terraform apply
```

## Operational Flow

The overall infrastructure relationship is:

```text
Terraform
    |
    v
VPC
    |
    v
EKS Cluster
    |
    +-------------------+
    |                   |
    v                   v
IAM               Managed Node Groups
    |                   |
    v                   v
Access Entries       EC2 Nodes
    |                   |
    +---------+---------+
              |
              v
          Kubernetes
              |
              v
            Pods
```

## Security Considerations

The module follows these principles:

- IAM roles are used instead of long-lived AWS access keys.
- EKS access is explicitly granted to required IAM principals.
- Worker nodes use dedicated IAM roles.
- OIDC enables workload-level AWS permissions.
- EKS control-plane logging is enabled.
- EKS is deployed into specified VPC subnets.
- Access policies should follow least-privilege principles.

## Interview Explanation

> "I created a reusable Terraform EKS module that provisions the EKS cluster, IAM roles, managed node groups, OIDC provider, EKS access entries, and required add-ons. I separated the Terraform code by responsibility so that cluster creation, IAM, access management, OIDC, node groups, and add-ons can be maintained independently while remaining part of the same reusable EKS module."

## Design Principle

The module intentionally keeps EKS-specific resources together.

```text
EKS Module
│
├── Cluster
├── Cluster IAM
├── Node IAM
├── Access Entries
├── OIDC
├── Node Groups
└── Add-ons
```

Generic AWS infrastructure such as the VPC, ECR, S3, and Terraform backend is maintained in separate modules.
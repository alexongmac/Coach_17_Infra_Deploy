## Provider
provider "aws" {
  region = "us-east-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.34"
    }
  }

  ## backend
  backend "s3" {
    bucket       = "sctp-tfstate-ce13"
    key          = "alex_s3/alex-coach17-terraform.tfstate"
    region       = "us-east-1"
    # S3 lockfiles disabled: bucket policy denies s3:DeleteObject for students,
    # so Terraform can create the .tflock but never release it.
    use_lockfile = false
  }

  required_version = ">= 1.10.0"
}

locals {
  name_prefix = "alex-coach17"
}

data "aws_caller_identity" "current" {}

data "aws_subnet" "ecs" {
  id = "subnet-00b4c98869b996d86"
}

resource "aws_security_group" "ecs" {
  name   = "${local.name_prefix}-ecs-sg"
  vpc_id = data.aws_subnet.ecs.vpc_id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecr_repository" "app" {
  name                 = "${local.name_prefix}-private-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # lets's terraform destroy to remove it even if it holds the images
}

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 7.5.0"

  cluster_name               = "${local.name_prefix}-ecs-cluster"
  cluster_capacity_providers = ["FARGATE"]

  services = {
    alex-task-def = { #task definition and service name -> #Change
      runtime_platform = {
        operating_system_family = "LINUX"
        cpu_architecture        = "ARM64"
      }
      cpu    = 512
      memory = 1024
      container_definitions = {
        alex-flask-container = { #container name -> Change
          essential = true
          image     = "${aws_ecr_repository.app.repository_url}:latest"
          port_mappings = [
            {
              containerPort = 8080
              protocol      = "tcp"
            }
          ]
        }
      }
      assign_public_ip                   = true
      deployment_minimum_healthy_percent = 100
      subnet_ids                         = ["subnet-00b4c98869b996d86", "subnet-07fe08d5909e677db"] #List of subnet IDs to use for your tasks
      security_group_ids                 = [aws_security_group.ecs.id]
    }
  }
}

module "github_oidc_bootstrap" {
  source                     = "./github-oidc-bootstrap"
  github_repository_username = "alexongmac"
  github_repository_name     = "Coach_17_InfraDeploy"
  github_oidc_role_name      = "${local.name_prefix}-github-oidc-role"
}

resource "aws_iam_role_policy" "github_oidc_policy" {
  name = "terraform-self-read-policy"
  role = module.github_oidc_bootstrap.github_oidc_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "OidcProviderList"
        Effect   = "Allow"
        Action   = "iam:ListOpenIDConnectProviders"
        Resource = "*"
      },
      {
        Sid      = "OidcProviderRead"
        Effect   = "Allow"
        Action   = "iam:GetOpenIDConnectProvider"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
      },
      {
        Sid    = "GithubOidcRoleRead"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies"
        ]
        Resource = module.github_oidc_bootstrap.github_oidc_role_arn
      }
    ]
  })

}

output "github_oidc_role_arn" {
  value = module.github_oidc_bootstrap.github_oidc_role_arn
}


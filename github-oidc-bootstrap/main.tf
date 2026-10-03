data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository_username}*/${var.github_repository_name}*:*"]
    }
  }
}


resource "aws_iam_role" "github_oidc" {
  name               = var.github_oidc_role_name
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

resource "aws_iam_role_policy_attachment" "deploy" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess",
    "arn:aws:iam::aws:policy/AmazonECS_FullAccess",
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
    "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess",
  ])
  role       = aws_iam_role.github_oidc.name
  policy_arn = each.value
}

# ECS module enables service autoscaling; no AWS managed policy above covers it
resource "aws_iam_role_policy" "app_autoscaling" {
  name = "application-autoscaling"
  role = aws_iam_role.github_oidc.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "application-autoscaling:*"
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "iam_full" {
  role       = aws_iam_role.github_oidc.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

variable "github_repository_username" {
  description = "GitHub repository username"
  type        = string
}

variable "github_repository_name" {
  description = "GitHub repository name"
  type        = string
}

variable "github_oidc_role_name" {
  description = "Name of the GitHub OIDC role"
  type        = string
}

output "github_oidc_role_arn" {
  value = aws_iam_role.github_oidc.arn
}

output "github_oidc_role_name" {
  value = aws_iam_role.github_oidc.name
}

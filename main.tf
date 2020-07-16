data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# The service role for the codebuild project. Gives codebuild the right to assume it.
resource "aws_iam_role" "main" {
  name = "${var.service_name}-code-build-service-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "codebuild.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

#####
# The base policy doc for the role - gives it the basics for what codebuild will need
# The calling code will need to add additional build-specific permissions
#####
data "aws_iam_policy_document" "main" {
  # S3 - Give access to the terraform remote states and artifacts bucket
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketAcl",
      "s3:GetBucketLocation",
    ]

    resources = [
      # Remote state access for terraform
      "${var.tf_remote_state_bucket_arn}",
      "${var.tf_remote_state_bucket_arn}/*",

      # Artifacts bucket for code build
      "${var.ci_cd_artifacts_bucket_arn}",
      "${var.ci_cd_artifacts_bucket_arn}/*",
    ]
  }

  # DDB - allow for state lock
  statement {
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:DeleteItem",
    ]

    resources = [
      var.tf_ddb_state_lock_table,
    ]
  }

  # Logs for this build
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs::log-group:/aws/codebuild/${var.service_name}-service-build",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.service_name}-service-build:*",
    ]
  }

  # Codebuild actions
  statement {
    effect = "Allow"

    actions = [
      "codebuild:*",
    ]

    resources = [
      "arn:aws:codebuild:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:project/*",
    ]
  }

  # SSM parameters - naming convention scoped to this project
  statement {
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]

    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/ci-cd/${var.service_name}/*",
    ]
  }

  # Encrypted SSM parameters
  statement {
    actions = ["kms:Decrypt"]

    resources = [
      var.kms_ssm_key_arn
    ]
  }
}

# Attach the policy to the role
resource "aws_iam_role_policy" "main" {
  role   = aws_iam_role.main.id
  policy = data.aws_iam_policy_document.main.json
}

# The actual build
resource "aws_codebuild_project" "service_build" {
  name          = "${var.service_name}-service-build"
  description   = "Used for pulling, building, testing and publishing applications resources"
  build_timeout = "90"
  service_role  = aws_iam_role.main.arn

  artifacts {
    type                = "S3"
    encryption_disabled = "false"
    location            = var.ci_cd_artifacts_bucket_arn
    path                = var.service_name
    namespace_type      = "BUILD_ID"
    packaging           = "ZIP"
  }

  cache {
    type = "LOCAL"

    modes = [
      "LOCAL_SOURCE_CACHE",
    ]
  }

  source {
    type     = "GITHUB"
    location = var.github_repo_url

    buildspec = "buildspec.yml"

    git_clone_depth     = "1"
    report_build_status = "true"

    auth {
      type = "OAUTH"
    }
  }

  environment {
    compute_type = var.compute_type

    image           = "aws/codebuild/standard:4.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = "true"

    environment_variable {
      name  = "SERVICE_NAME"
      value = var.service_name
    }
  }
}

# Set up a webhook - requires github to already be authorized
resource "aws_codebuild_webhook" "main" {
  project_name = aws_codebuild_project.service_build.name

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH"
    }

    filter {
      type    = "HEAD_REF"
      pattern = "^refs/heads/${var.main_branch}$"
    }
  }
}

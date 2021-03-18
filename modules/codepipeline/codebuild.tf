data "aws_caller_identity" "current" {}

resource "aws_iam_role" "notejam_codebuild_role" {
  name               = "notejam_codebuild_role"
  assume_role_policy = <<ASSUME
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "sts:AssumeRole"
            ],
            "Effect": "Allow",
            "Principal": {
                "Service": [
                    "codebuild.amazonaws.com"
                ]
            }
        }
    ]
}
ASSUME
}

data "aws_iam_policy_document" "codebuild_policy_doc" {
  statement {
    actions = [
      "ecr:*",
      "ecs:DescribeTaskDefinition",
      "logs:*",
      "s3:*",
      "ec2:*",
      "secretsmanager:GetSecretValue"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "codebuild_policy" {
  name   = "notejam_codebuild_policy"
  policy = data.aws_iam_policy_document.codebuild_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "codebuild_policy_attachment" {
  role       = aws_iam_role.notejam_codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}

## Codebuild notejam
data "template_file" "buildspec_notejam" {
  template = file("${path.module}/specs/buildspec.build.notejam.yml")
  vars = {
    AWS_DEFAULT_REGION = "ap-southeast-2"
    AWS_ACCOUNT_ID     = data.aws_caller_identity.current.account_id
  }
}

resource "aws_codebuild_project" "notejam_build" {
  badge_enabled  = false
  build_timeout  = 60
  name           = "notejam-build"
  queued_timeout = 480
  service_role   = aws_iam_role.notejam_codebuild_role.arn
  tags           = {}

  artifacts {
    encryption_disabled    = false
    name                   = "notejam-build"
    override_artifact_name = false
    packaging              = "NONE"
    type                   = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:4.0"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
    type                        = "LINUX_CONTAINER"

    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = "notejam"
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.account_id
    }

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.region
    }

    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }

    environment_variable {
      name  = "SERVICE_PORT"
      value = "5000"
    }

    environment_variable {
      name  = "TASK_DEFINITION"
      value = var.task_definition_family
    }

    environment_variable {
      name = "SECURITY_GROUP"
      value = aws_security_group.ci_sec_group.id
    }

    environment_variable {
      name  = "SUBNETS"
      value = jsonencode(var.vpc_subnets)
    }
    # environment_variable {
    #   name  = "DB_ENDPOINT"
    #   value = "docker/credentials"
    #   type = "SECRETS_MANAGER"
    # }
  }

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }

    s3_logs {
      encryption_disabled = false
      status              = "DISABLED"
    }
  }

  source {
    buildspec           = data.template_file.buildspec_notejam.rendered
    git_clone_depth     = 0
    insecure_ssl        = false
    report_build_status = false
    type                = "CODEPIPELINE"
  }
}


resource "aws_security_group" "ci_sec_group" {
  name   = "ci-security-group"
  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Create BitBucket connection
resource "aws_codestarconnections_connection" "notejam_repo" {
  name          = "github-connection"
  provider_type = "GitHub"
}

# Create ECR Repo

resource "aws_ecr_repository" "notejam" {
  name = "notejam"
}

resource "aws_ecr_lifecycle_policy" "notejampolicy" {
  repository = aws_ecr_repository.notejam.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 30 images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["v"],
                "countType": "imageCountMoreThan",
                "countNumber": 30
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

# Artifacts bucket
resource "aws_s3_bucket" "notejam_codepipeline_artifacts" {
  bucket = "notejam-codepipeline-artifacts"
  versioning {
    enabled = true
  }
}

## Codepipeline
resource "aws_iam_role" "notejam_codepipeline_role" {
  name               = "notejam_codepipeline_role"
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
                    "codepipeline.amazonaws.com",
                    "codebuild.amazonaws.com",
                    "ec2.amazonaws.com"
                ]
            }
        }
    ]
}
ASSUME
}

data "aws_iam_policy_document" "codepipeline_policy_doc" {
  statement {
    actions = [
      "s3:*",
      "logs:*",
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
      "codedeploy:*",
      # "codedeploy:CreateDeployment",
      # "codedeploy:GetApplication",
      # "codedeploy:GetApplicationRevision",
      # "codedeploy:GetDeployment",
      # "codedeploy:GetDeploymentConfig",
      # "codedeploy:RegisterApplicationRevision",
      "codestar-connections:UseConnection",
      "codestar-connections:GetConnection",
      "codestar-connections:ListConnections",
      "ecs:*"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "codepipeline_policy" {
  name   = "notejam_codepipeline_policy"
  policy = data.aws_iam_policy_document.codepipeline_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy_attachment" {
  role       = aws_iam_role.notejam_codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_policy.arn
}

resource "aws_codepipeline" "notejam_pipeline" {
  name     = "notejam-build-pipeline"
  role_arn = aws_iam_role.notejam_codepipeline_role.arn
  tags     = {}

  artifact_store {
    location = aws_s3_bucket.notejam_codepipeline_artifacts.id
    type     = "S3"
  }

  stage {
    name = "SourceApp"

    action {
      category = "Source"
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.notejam_repo.arn
        FullRepositoryId = var.github_repo_name
        BranchName       = var.github_repo_branch
        DetectChanges    = true
      }
      input_artifacts = []
      name            = "Source"
      output_artifacts = [
        "SourceArtifact",
      ]
      owner     = "AWS"
      provider  = "CodeStarSourceConnection"
      run_order = 1
      version   = "1"
    }
    # action {
    #   category = "Source"
    #   configuration = {
    #     S3Bucket = aws_s3_bucket.notejam_codepipeline_artifacts.id
    #     S3ObjectKey = "notejam-app-master.zip"
    #   }
    #   input_artifacts = []
    #   name            = "Source"
    #   output_artifacts = [
    #     "SourceArtifact",
    #   ]
    #   owner     = "AWS"
    #   provider  = "S3"
    #   run_order = 1
    #   version   = "1"
    # }
  }
  stage {
    name = "Build"

    action {
      category = "Build"
      configuration = {
        "EnvironmentVariables" = jsonencode(
          [
            # {
            #   name  = "environment"
            #   type  = "PLAINTEXT"
            #   value = var.env
            # },
          ]
        )
        "ProjectName" = "notejam-build"
      }
      input_artifacts = [
        "SourceArtifact",
      ]
      name             = "Buildnotejam"
      output_artifacts = ["BuildArtifact"]
      owner            = "AWS"
      provider         = "CodeBuild"
      run_order        = 1
      version          = "1"
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "DeployToECS"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      input_artifacts = ["BuildArtifact"]
      version         = "1"

      configuration = {
        ApplicationName                = "notejam"
        DeploymentGroupName            = "notejam"
        TaskDefinitionTemplateArtifact = "BuildArtifact"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "BuildArtifact"
        AppSpecTemplatePath            = "appspec.yml"
      }
    }
  }
}
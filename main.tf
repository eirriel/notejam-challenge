provider "aws" {
  region = "ap-southeast-2"
}

terraform {
  required_version = "0.14.7"

  backend "s3" {
    bucket  = "notejam-terraform-state"
    region  = "ap-southeast-2"
    key     = "aws/notejam-state-file.tfstate"
    encrypt = true
  }
}

locals {
  mgmt_ips = ["158.140.229.101/32", "192.168.4.0/24", "192.168.9.0/24"]
}

# Get information from the account
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "notejam_ct_logs" {
  bucket = "notejam-ct-logs"
}

resource "aws_s3_bucket_policy" "ct_bucket_policy" {
  bucket = aws_s3_bucket.notejam_ct_logs.id

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AWSCloudTrailAclCheck20150319",
            "Effect": "Allow",
            "Principal": {"Service": "cloudtrail.amazonaws.com"},
            "Action": "s3:GetBucketAcl",
            "Resource": "arn:aws:s3:::notejam-ct-logs"
        },
        {
            "Sid": "AWSCloudTrailWrite20150319",
            "Effect": "Allow",
            "Principal": {"Service": "cloudtrail.amazonaws.com"},
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::notejam-ct-logs/*",
            "Condition": {"StringEquals": {"s3:x-amz-acl": "bucket-owner-full-control"}}
        }
    ]
})
}

# Create IAM role for ECS access
resource "aws_iam_role" "cloudtrail_iam_role" {
  name = "iam-role-cloudtrail"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid : "",
        Effect : "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action : [
          "sts:AssumeRole"
        ],
      }
    ]
  })
  managed_policy_arns = ["arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"]
}

# # Create IAM policy for ECS access with data as source
# resource "aws_iam_role_policy" "ct_iam_role_policy_attach" {
#   policy = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
#   name   = "cloudtrail-role"
#   role   = aws_iam_role.cloudtrail_iam_role.id
# }

resource "aws_cloudwatch_log_group" "ct_logs" {
  name = "cloudtrail-logs"
}

resource "aws_cloudtrail" "main" {
  name           = "trail-main"
  s3_bucket_name = aws_s3_bucket.notejam_ct_logs.id
  include_global_service_events = true
  cloud_watch_logs_role_arn = aws_iam_role.cloudtrail_iam_role.arn
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.ct_logs.arn}:*"
}


# Create a VPC
module "vpc" {
  source             = "terraform-aws-modules/vpc/aws"
  version            = "2.70.0"
  cidr               = var.vpc_cidr
  name               = "notejam-vpc"
  private_subnets    = var.private_subnets
  public_subnets     = var.public_subnets
  database_subnets   = var.db_subnets
  enable_nat_gateway = true
  single_nat_gateway = true
  create_igw         = true
  azs = [
    "ap-southeast-2a",
  "ap-southeast-2b"]
}

# Create Security group for LB
resource "aws_security_group" "lb-sec-group" {
  name   = "lb-security-group"
  vpc_id = module.vpc.vpc_id
  ingress {
    from_port   = 80
    to_port     = 80
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
# Create Security group for Instance
resource "aws_security_group" "instance_sec_group" {
  name   = "instance-security-group"
  vpc_id = module.vpc.vpc_id
  ingress {
    from_port       = 32768
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.lb-sec-group.id]
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "tcp"
    cidr_blocks = ["158.140.229.101/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create ALB
resource "aws_lb" "alb" {
  name                       = "notejam-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.lb-sec-group.id]
  subnets                    = module.vpc.public_subnets
  enable_deletion_protection = false
}

#Create LB listener
resource "aws_lb_listener" "notejam_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lb_tg_bluegreen1.id
  }
}

# Instance target group 1
resource "aws_lb_target_group" "lb_tg_bluegreen1" {
  name        = "lb-tg-bluegreen1"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  health_check {
    path                = "/"
    interval            = 10
    unhealthy_threshold = 5
    matcher = "200,302"
  }

  stickiness {
    type = "lb_cookie"
    enabled = true
  }

  depends_on = [aws_lb.alb]

}

# Instance target group 2
resource "aws_lb_target_group" "lb_tg_bluegreen2" {
  name        = "lb-tg-bluegreen2"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  health_check {
    path                = "/"
    interval            = 10
    unhealthy_threshold = 5
    matcher = "200,302"
  }

  stickiness {
    type = "lb_cookie"
    enabled = true
  }
  
  depends_on = [aws_lb.alb]

}

module "notejam_ci" {
  source                 = "./modules/codepipeline"
  account_id             = data.aws_caller_identity.current.account_id
  region                 = "ap-southeast-2"
  vpc_id                 = module.vpc.vpc_id
  vpc_subnets            = module.vpc.private_subnets
  github_repo_name       = var.github_repo_name
  github_repo_branch     = var.github_repo_branch
  alb_target_group_blue  = aws_lb_target_group.lb_tg_bluegreen1.name
  alb_target_group_green = aws_lb_target_group.lb_tg_bluegreen2.name
  ecs_cluster_name       = aws_ecs_cluster.cluster.name
  ecs_service_name       = aws_ecs_service.service.name
  listener_arns          = [aws_lb_listener.notejam_listener.arn]
  task_definition_family = aws_ecs_task_definition.task-def.arn
}
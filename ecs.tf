# Create IAM Policy
data "aws_iam_policy_document" "ecs_agent" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
# Create IAM role
resource "aws_iam_role" "ecs_agent_role" {
  name               = "ecs-agent"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent.json
}
# Attach policy to created role
resource "aws_iam_role_policy_attachment" "ecs_policy_attach" {
  role       = aws_iam_role.ecs_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
# Created Instance profile to be attached to EC2
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs-instance_profile"
  role = aws_iam_role.ecs_agent_role.name
}

# Importing key pair
resource "aws_key_pair" "ae" {
  key_name   = "ae"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDqBLaEjYbHNuLPcUCYSDC+rHZuQPXyXWD+hZu55jjx2zVxfrT9hNUYoNS6GvZPJD7qzWVNlXN3WtO5IxCEpG4WHFGzZuiD8wru7WeioSra7xovljvC2WLU8bG27fterR+/HHSOmwyfpflfimnysqC87FK02EBye/V7GD0xMQAPXl1SSRuAyXq91hKP7dHaIMPsuHp+elSppN8viaisWc5sOyj7dQLiWghcsvH/Vw5uplMlJNmXx6OfArbVSn7AyyZYqIWi3e5iR47kR3x67/0nZcXaZEq+jiHWpQ/n1k9AI+RSVaqV3Be4Gzy5FjF25i02AqQs/2ZvvXL/xh4kOT81"
}

# Create Launch configuration
resource "aws_launch_configuration" "ecs_launch_config" {
  image_id             = "ami-016f6cf165ef55d02" # AWS ECS Optimized AMI for ap-southeast-2
  iam_instance_profile = aws_iam_instance_profile.ecs_instance_profile.name
  security_groups      = [aws_security_group.instance_sec_group.id]
  instance_type        = "t3.small"
  key_name             = aws_key_pair.ae.id
  user_data            = "#!/bin/bash\necho ECS_CLUSTER=${aws_ecs_cluster.cluster.name} >> /etc/ecs/ecs.config"
}

# Create autoscaling group
resource "aws_autoscaling_group" "auto-scaling" {
  desired_capacity     = 2
  max_size             = 6
  min_size             = 1
  launch_configuration = aws_launch_configuration.ecs_launch_config.name
  vpc_zone_identifier = [
    module.vpc.public_subnets[0],
  module.vpc.public_subnets[1]]
}

# Create ECS Capacity provider
resource "aws_ecs_capacity_provider" "ecs-cap" {
  name = "notejam-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.auto-scaling.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 10
      minimum_scaling_step_size = 1
      status                    = "DISABLED"
      target_capacity           = 10
    }
  }
}

# Create IAM policy data for ECS access
data "aws_iam_policy_document" "ecs_iam_policy" {
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "elasticloadbalancing:Describe*",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
      "ec2:Describe*",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2: *",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

# Create IAM role for ECS access
resource "aws_iam_role" "ecs_iam_role" {
  name = "iam-role-ecs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid : "",
        Effect : "Allow",
        Principal = {
          Service = "ecs.amazonaws.com"
        },
        Action : [
          "sts:AssumeRole"
        ],
      }
    ]
  })
}
# Create IAM policy for ECS access with data as source
resource "aws_iam_role_policy" "ecs_iam_role_policy" {
  policy = data.aws_iam_policy_document.ecs_iam_policy.json
  name   = "ecs-assume-role"
  role   = aws_iam_role.ecs_iam_role.id
}

# Create ECS cluster
resource "aws_ecs_cluster" "cluster" {
  name = "notejam-cluster"
}

# Create ECS Service
resource "aws_ecs_service" "service" {
  name            = "ecs-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.task-def.arn
  desired_count   = 2
  iam_role        = aws_iam_role.ecs_iam_role.arn

  load_balancer {
    target_group_arn = aws_lb_target_group.lb_tg_bluegreen1.arn
    container_name   = "notejam"
    container_port   = 5000
  }

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  depends_on = [aws_lb.alb]
}

#Create task definition
resource "aws_ecs_task_definition" "task-def" {
  family                = "service"
  container_definitions = data.template_file.container-file-def.rendered
}

data "template_file" "container-file-def" {
  template = file("${path.root}/container_def.json")
  vars = {
    ACCOUNT_ID         = data.aws_caller_identity.current.account_id
    AWS_DEFAULT_REGION = "ap-southeast-2"
    REPOSITORY_URI     = module.notejam_ci.ecr_repo
    TAG                = var.app_tag
  }
}

# Creating log group
resource "aws_cloudwatch_log_group" "notejam_logs" {
  name = "notejam-logs"
}
resource "aws_iam_role" "notejam_codedeploy_role" {
  name               = "notejam_codedeploy_role"
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
                    "codedeploy.amazonaws.com"
                ]
            }
        }
    ]
}
ASSUME
}

resource "aws_iam_role_policy_attachment" "AWSCodeDeployRole_attach" {
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
  role       = aws_iam_role.notejam_codedeploy_role.name
}

resource "aws_codedeploy_app" "notejam" {
  compute_platform = "ECS"
  name             = "notejam"
}

resource "aws_codedeploy_deployment_group" "notejam" {
  app_name               = aws_codedeploy_app.notejam.name
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  deployment_group_name  = "notejam"
  service_role_arn       = aws_iam_role.notejam_codedeploy_role.arn

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = var.ecs_cluster_name # aws_ecs_cluster.notejam-cluster.name
    service_name = var.ecs_service_name # aws_ecs_service.service.name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = var.listener_arns # [aws_lb_listener.notejam_listener.arn]
      }

      target_group {
        name = var.alb_target_group_blue # aws_lb_target_group.lb_tg_bluegreen1.name
      }

      target_group {
        name = var.alb_target_group_green # aws_lb_target_group.lb_tg_bluegreen2.name
      }
    }
  }
}
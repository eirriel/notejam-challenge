variable "vpc_id" {
  type = string
}

variable "vpc_subnets" {
  type = list(string)
}

variable "github_repo_name" {
  type = string
}

variable "github_repo_branch" {
  type = string
}

variable "alb_target_group_blue" {
  type = string
}

variable "alb_target_group_green" {
  type = string
}
variable "vpc_cidr" {
  type    = string
  default = "192.168.34.0/24"
}

variable "public_subnets" {
  type    = list(string)
  default = ["192.168.34.0/26", "192.168.34.64/26"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["192.168.34.128/27", "192.168.34.160/27"]
}

variable "db_subnets" {
  type    = list(string)
  default = ["192.168.34.192/27", "192.168.34.224/27"]
}

variable "app_tag" {
    type = string
    default = "latest"
}
variable "github_repo_name" {
    type = string
    default = "eirriel/notejam"
}

variable "github_repo_branch" {
    type = string
    default = "terraform"
}
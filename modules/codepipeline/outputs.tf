output "ci_sec_grp" {
  value = aws_security_group.ci_sec_group.id
}

output "ecr_repo" {
  value = aws_ecr_repository.notejam.repository_url
}
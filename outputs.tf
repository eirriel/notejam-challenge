output "db_user" {
  value = aws_db_instance.db.username
}

output "db_password" {
  value = random_password.db_password.result
}

output "db_host" {
  value = aws_db_instance.db.address
}

output "app_endpoint" {
  value = aws_lb.alb.dns_name
}
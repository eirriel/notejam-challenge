# Create DB security group
resource "aws_security_group" "db_sec_group" {
  name   = "db-security-group"
  vpc_id = module.vpc.vpc_id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.instance_sec_group.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Using resource to generate random password

resource "random_password" "db_password" {
  length  = 16
  special = false
}

# Create DB in RDS PostgreSQL
resource "aws_db_instance" "db" {
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "5.6.44"
  instance_class         = "db.t3.micro"
  name                   = "notejamdb"
  username               = "root"
  password               = random_password.db_password.result
  multi_az               = true
  db_subnet_group_name   = module.vpc.database_subnet_group
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.db_sec_group.id]
}

# Storing the credentials in Secret Manager
resource "aws_secretsmanager_secret" "db_endpoint" {
  name = "db_credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_endpoint_value" {
  secret_id     = aws_secretsmanager_secret.db_endpoint.id
  secret_string = "mysql://${aws_db_instance.db.username}:${random_password.db_password.result}@${aws_db_instance.db.address}:3306/notejam"
}


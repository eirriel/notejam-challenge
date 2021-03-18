# notejam-challenge
## Architecture Overview

The Notejam application runs in a single container deployed in ECS for scalability and interaction with other services. The image was built with additional configuration in order to switch from the default database (SQLite) to an external database running in RDS

![Architecture Diagram](/docs/notejam-diagram.jpg)

## Backups

Database backups relay on RDS snapshots

## Deployments

CI/CD is provided through AWS CodePipeline. The deployment is managed by CodeDeploy in a blue-green strategy.
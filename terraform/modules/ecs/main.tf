# ECS (Elastic Container Service) setup
resource "aws_ecs_cluster" "nestjs_notes_cluster" {
  name = var.ecs_cluster_name
}

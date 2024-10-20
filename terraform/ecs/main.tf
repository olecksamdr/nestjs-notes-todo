# https://medium.com/@vladkens/aws-ecs-cluster-on-ec2-with-terraform-2023-fdb9f6b7db07

resource "aws_ecs_cluster" "main" {
  name = var.name
}

# Launch Template (describes EC2 instance)
resource "aws_launch_template" "ecs_ec2" {
  name_prefix            = var.name_prefix
  image_id               = var.ami_id
  instance_type          = var.ec2_instance_type

  monitoring { enabled = true }

  network_interfaces {
    associate_public_ip_address = true
  }

  instance_market_options {
    market_type = "spot"
  }

  block_device_mappings {
    device_name = "/dev/sdf"

    ebs {
      # TODO: move to the variable
      volume_size = 8
    }
  }

  # In user_data you is required to pass ECS cluster name,
  # so AWS can register EC2 instance as node of ECS cluster
  user_data = base64encode(<<-EOF
      #!/bin/bash
      echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config;
    EOF
  )
}

# Autoscaling Group
resource "aws_autoscaling_group" "ecs" {
  vpc_zone_identifier       = var.vpc_zone_identifier
  min_size                  = var.autoscaling_gorup_min_size
  max_size                  = var.autoscaling_gorup_max_size
  desired_capacity          = var.autoscaling_gorup_desired_capacity
  health_check_type         = "EC2"

  launch_template {
    id      = aws_launch_template.ecs_ec2.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = aws_ecs_cluster.main.name
    propagate_at_launch = true
  }

  # Associating an ECS Capacity Provider to an Auto Scaling Group
  # will automatically add the AmazonECSManaged tag to the Auto Scaling Group.
  # This tag should be included in the aws_autoscaling_group resource configuration
  # to prevent Terraform from removing it in subsequent executions as well as ensuring
  # the AmazonECSManaged tag is propagated to all EC2 Instances in the Auto Scaling Group
  # if min_size is above 0 on creation. Any EC2 Instances in the Auto Scaling Group
  # without this tag must be manually be updated, otherwise they may cause unexpected scaling
  # behavior and metrics.
  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }
}

# Connect the ECS Cluster to the ASG group so that the cluster
# can use EC2 instances to deploy containers
resource "aws_ecs_capacity_provider" "main" {
  name = var.name

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 2
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.main.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.main.name
    base              = 1
    weight            = 100
  }
}

# IAM Role for ECS Task
# Roles required to have access ECR, Cloud Watch

data "aws_iam_policy_document" "ecs_task_doc" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_role" {
  name_prefix        = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_doc.json
}

resource "aws_iam_role" "ecs_exec_role" {
  name_prefix        = "${var.name}-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_doc.json
}

resource "aws_iam_role_policy_attachment" "ecs_exec_role_policy" {
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition
# At this point, we simply describe from where
# and how to launch the docker container.

resource "aws_ecs_task_definition" "app" {
  family             = var.name
  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_exec_role.arn
  network_mode       = "awsvpc"

  container_definitions = jsonencode([{
    name         = "${var.name}-container",
    image        = "${var.ecr_repository_url}:latest",
    # If the essential parameter of a container is marked as true,
    # and that container fails or stops for any reason,
    # all other containers that are part of the task are stopped.
    # If the essential parameter of a container is marked as false,
    # its failure doesn't affect the rest of the containers in a task.
    # If this parameter is omitted, a container is assumed to be essential.
    essential    = true,
    portMappings = [{ containerPort = 80, hostPort = 80 }],

    # TODO:
    # logConfiguration = {
    #   logDriver = "awslogs",
    #   options = {
    #     "awslogs-region"        = "us-east-1",
    #     "awslogs-group"         = aws_cloudwatch_log_group.ecs.name,
    #     "awslogs-stream-prefix" = "app"
    #   }
    # },
  }])
}

resource "aws_security_group" "http_and_https" {
  name_prefix = "http-and-https-sg-"
  description = "Allow all HTTP/HTTPS traffic from public"
  vpc_id      =  var.vpc_id

  dynamic "ingress" {
    for_each = [80, 443]
    content {
      protocol    = "tcp"
      from_port   = ingress.value
      to_port     = ingress.value
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}
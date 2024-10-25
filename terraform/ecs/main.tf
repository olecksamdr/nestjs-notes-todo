# https://medium.com/@vladkens/aws-ecs-cluster-on-ec2-with-terraform-2023-fdb9f6b7db07

resource "aws_ecs_cluster" "main" {
  name = var.name
}

# Create a key pair to access ec2 instance by ssh
resource "aws_key_pair" "ssh" {
  key_name   = "ssh-ec2-access"
  public_key = var.ssh_public_key
}

# IAM Role & Security Group for ECS EC2 Node
# Amazon ECS container instances, including both Amazon EC2
# and external instances, run the Amazon ECS container agent
# and require an IAM role for the service to know that the agent
# belongs to you. Before you launch container instances and register
# them to a cluster, you must create an IAM role for your container
# instances to use.
#
# Amazon ECS provides the AmazonEC2ContainerServiceforEC2Role managed 
# IAM policy which contains the permissions needed to use the full
# Amazon ECS feature set. This managed policy can be attached
#  to an IAM role and associated with your container instances. 
# 
# You can manually create the role and attach 
# the managed IAM policy for container instances to allow
# Amazon ECS to add permissions for future features and enhancements
# as they are introduced
#
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/instance_IAM_role.html

data "aws_iam_policy_document" "ecs_node_doc" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_node_role" {
  name_prefix        = var.name
  assume_role_policy = data.aws_iam_policy_document.ecs_node_doc.json
}

resource "aws_iam_role_policy_attachment" "ecs_node_role_policy" {
  role       = aws_iam_role.ecs_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_node" {
  name_prefix = var.name
  path        = "/ecs/instance/"
  role        = aws_iam_role.ecs_node_role.name
}

resource "aws_security_group" "ssh" {
  name_prefix = "SSH ${var.name}"
  description = "Allow SSH connection"
  vpc_id      = var.vpc_id

  # ssh 
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "http_and_https" {
  name_prefix = "http-and-https-sg-"
  description = "Allow all HTTP/HTTPS traffic from public"
  vpc_id      = var.vpc_id

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

# Launch Template (describes EC2 instance)
data "aws_ssm_parameter" "ecs_node_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_launch_template" "ecs_ec2" {
  name_prefix   = var.name_prefix
  image_id      = data.aws_ssm_parameter.ecs_node_ami.value
  instance_type = var.ec2_instance_type
  key_name      = aws_key_pair.ssh.key_name

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_node.arn
  }

  monitoring {
    enabled = true
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [
      aws_security_group.ssh.id,
      aws_security_group.http_and_https.id
    ]
  }

  block_device_mappings {
    device_name = "/dev/sdf"

    ebs {
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
  vpc_zone_identifier = var.public_subnets
  min_size            = var.autoscaling_gorup_min_size
  max_size            = var.autoscaling_gorup_max_size
  desired_capacity    = var.autoscaling_gorup_desired_capacity
  health_check_type   = "EC2"

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

# Retrieve Secrets Manager secrets through Amazon ECS environment variables
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/secrets-envvar-secrets-manager.html

resource "aws_secretsmanager_secret" "db_url" {
  name        = "DATABASE_URL"
  description = "DATABASE_URL for ${var.name}"
  # set the recovery window to 0 for immediate deletion of secrets after calling terraform destroy
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_url" {
  secret_id     = aws_secretsmanager_secret.db_url.id
  secret_string = var.DATABASE_URI
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

data "aws_iam_policy_document" "ecs_task_secrets_policy_doc" {
  version = "2012-10-17"
  # Your task definition must use a task execution role with the additional permissions for Secrets Manager.
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/secrets-envvar-secrets-manager.html
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db_url.arn]
  }
}

resource "aws_iam_policy" "get_secret_value" {
  name        = "GetSecretValue-policy"
  description = "A test policy"
  policy      = data.aws_iam_policy_document.ecs_task_secrets_policy_doc.json
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
  for_each = tomap({
    get_secret = aws_iam_policy.get_secret_value.arn,
    task_exec  = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  })
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = each.value
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "cloud-watch-${var.name}"
  retention_in_days = 1
}

data "aws_region" "current" {}

# ECS Task Definition
# At this point, we simply describe from where
# and how to launch the docker container.

locals {
  container_name = "${var.name}-container"
  container_port = 80
}

resource "aws_ecs_task_definition" "app" {
  family             = var.name
  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_exec_role.arn

  # Amazon EC2 — You can launch EC2 instances on a public subnet.
  # Amazon ECS uses these EC2 instances as cluster capacity,
  # and any containers that are running on the instances can use
  # the underlying public IP address of the host for outbound networking.
  # This applies to both the *host* and *bridge* network modes.
  # 
  # However, the *awsvpc* network mode doesn't provide task ENIs with public IP addresses.
  # Therefore, they can’t make direct use of an internet gateway.
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/networking-outbound.html

  # With bridge mode, you're using a virtual network bridge to create a layer between the host
  # and the networking of the container.
  # This way, you can create port mappings that remap a host port to a container port.
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/networking-networkmode-bridge.html
  network_mode = "bridge"
  cpu          = 1024
  memory       = 256

  container_definitions = jsonencode([{
    name  = local.container_name,
    image = "${var.ecr_repository_url}:latest",
    # If the essential parameter of a container is marked as true,
    # and that container fails or stops for any reason,
    # all other containers that are part of the task are stopped.
    # If the essential parameter of a container is marked as false,
    # its failure doesn't affect the rest of the containers in a task.
    # If this parameter is omitted, a container is assumed to be essential.
    essential = true,

    environment = [{
      name  = "PORT"
      value = "80"
    }]

    portMappings = [{
      hostPort      = 80,
      containerPort = local.container_port,
    }],

    secrets = [{
      name      = aws_secretsmanager_secret.db_url.name
      valueFrom = aws_secretsmanager_secret_version.db_url.arn
    }]

    logConfiguration = {
      logDriver = "awslogs",
      options = {
        "awslogs-region"        = data.aws_region.current.name,
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name,
        "awslogs-stream-prefix" = "ecs"
      }
    },
  }])
}

# Load Balancer (ALB)

resource "aws_lb" "main" {
  name               = "alb-for-${var.name}"
  load_balancer_type = "application"
  subnets            = var.public_subnets
  security_groups    = [aws_security_group.http_and_https.id]

  tags = {
    Name = "alb-for=${var.name}"
  }
}

resource "aws_lb_target_group" "app" {
  name_prefix = substr(var.name, 1, 6)
  vpc_id      = var.vpc_id
  # TODO https and redirect from http to https
  protocol    = "HTTP"
  port        = 80
  target_type = "instance"

  health_check {
    enabled = true
    path    = "/api/v1/note/all"
    port    = 80
    matcher = 200
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Create a security group
# Container instances require external network access
# to communicate with the Amazon ECS service endpoint.
# 
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/get-set-up-for-amazon-ecs.html

# You only need to configure the security group in the ECS service
# network configuration and AWS will automatically attach that security group 
# to the registered ECS optimized EC2 instance the ECS service task 
# is running on.

# https://stackoverflow.com/questions/76855816/how-do-aws-ecs-container-security-groups-work-on-ecs-optimized-ec2-instances

resource "aws_ecs_service" "app" {
  name            = "${var.name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1


  depends_on = [aws_lb_target_group.app]

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = local.container_name
    container_port   = local.container_port
  }

  # network_configuration - (Optional)
  # Network configuration for the service.
  # This parameter is required for task definitions that use the awsvpc network mode
  # to receive their own Elastic Network Interface, and it is not supported for other network modes.
  # 
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service.html#network_configuration

  network_configuration {
    security_groups = [aws_security_group.http_and_https.id]
    subnets         = var.public_subnets
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.main.name
    base              = 1
    weight            = 100
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

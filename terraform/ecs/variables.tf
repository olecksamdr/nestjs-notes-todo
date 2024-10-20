variable "name" {
  description = "ECS cluster name"
  type = string
}

variable "name_prefix" {
  type = string
  default = "ecs"
}

variable ec2_instance_type {
  type = string
  default = "t2.micro"
}

variable ami_id {
  type = string
  default = "ami-08ec94f928cf25a9d" # Amazon linux 2023 64-bit (Arm)
}

# Autoscaling Group

variable vpc_zone_identifier {
  type = list
}

variable autoscaling_gorup_max_size {
  type = number
  default = 2
}

variable autoscaling_gorup_min_size {
  type = number
  default = 0
}

variable autoscaling_gorup_desired_capacity {
  type = number
  default = 1
}

# ECS Task Definition
variable ecr_repository_url {
  type = string
}

variable vpc_id {
  type = string
}
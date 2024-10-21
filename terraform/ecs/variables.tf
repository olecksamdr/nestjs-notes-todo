variable "ssh_public_key" {
  type    = string
  default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKbOiwa9YjatCr+NBJnIRQ6/rbF0u0RrZhQ7SxOYTUEU velsashok@gmail.com"
}

variable "name" {
  description = "ECS cluster name"
  type        = string
}

variable "name_prefix" {
  type    = string
  default = "ecs"
}

variable "ec2_instance_type" {
  type    = string
  default = "t2.micro"
}

variable "ami_id" {
  type    = string
  default = "ami-08ec94f928cf25a9d" # Amazon linux 2023 64-bit (Arm)
}

# Autoscaling Group

variable "public_subnets" {
  type = list(any)
}

variable "autoscaling_gorup_max_size" {
  type    = number
  default = 2
}

variable "autoscaling_gorup_min_size" {
  type    = number
  default = 1
}

variable "autoscaling_gorup_desired_capacity" {
  type    = number
  default = 1
}

# ECS Task Definition
variable "ecr_repository_url" {
  type = string
}

variable "vpc_id" {
  type = string
}
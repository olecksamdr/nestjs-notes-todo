terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.72.0"
    }
  }
}

provider "aws" {
  # Europe (Frankfurt)
  region = "eu-central-1"
}

# DNS
# Create an AWS Route53 hosted zone
# it represents a collection of records
# that can be managed together, belonging to a single parent domain name
resource "aws_route53_zone" "primary" {
  name = "nestjs-notes.online"
}

# Create a ECR Container Registry
resource "aws_ecr_repository" "nestjs_notes_ecr_repo" {
  name = "nestjs-notes-ecr-repo"
}

# Create IAM user which can push images to the ECR
resource "aws_iam_user" "nestjs_notes_ecr_user" {
  name = "nestjs_notes_ecr_user"

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Allow to manage ECR
resource "aws_iam_user_policy_attachment" "container_registry_power_user" {
  user       = aws_iam_user.nestjs_notes_ecr_user.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.14.0"

  name = "terraform-vpc"
  cidr = "172.32.0.0/16"

  azs            = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  public_subnets = ["172.32.101.0/24", "172.32.102.0/24", "172.32.103.0/24"]

  enable_nat_gateway     = false
  single_nat_gateway     = false
  one_nat_gateway_per_az = false

  tags = {
    Terraform = "true"
  }
}

module "ecs" {
  source = "./terraform/ecs"

  name               = "nestjs_notes_cluster"
  vpc_id             = module.vpc.vpc_id
  public_subnets     = module.vpc.public_subnets
  ecr_repository_url = aws_ecr_repository.nestjs_notes_ecr_repo.repository_url
  DATABASE_URI       = var.DATABASE_URI
}

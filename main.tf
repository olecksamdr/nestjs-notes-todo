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

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.14.0"

  name = "terraform-vpc"
  cidr = "172.32.0.0/16"

  azs = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  public_subnets  = ["172.32.101.0/24", "172.32.102.0/24", "172.32.103.0/24"]

  enable_nat_gateway = false
  single_nat_gateway = false
  one_nat_gateway_per_az = false

  tags = {
    Terraform = "true"
  }
}

module "ecs" {
  source           = "./terraform/modules/ecs"
  ecs_cluster_name = "nestjs_notes_cluster"
}

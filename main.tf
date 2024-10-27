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

locals {
  domain_name = "nestjs-notes.online"
}

resource "aws_route53_zone" "primary" {
  name = local.domain_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.primary.zone_id
  # If you're creating a record that has the same name as the hosted zone,
  # don't enter a value (for example, an @ symbol) in the Name field.
  # https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-values-basic.html#rrsets-values-basic-name
  name = "www"
  type = "A"

  alias {
    name                   = local.domain_name
    zone_id                = aws_route53_zone.primary.zone_id
    evaluate_target_health = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Create a ECR Container Registry
resource "aws_ecr_repository" "nestjs_notes_ecr_repo" {
  name = "nestjs-notes-ecr-repo"
}

# Create IAM user which can push images to the ECR
resource "aws_iam_user" "nestjs_notes_github_user" {
  name = "nestjs_notes_github_actions_user"

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Allow to manage ECR and update ECS Service

data "aws_iam_policy_document" "deploy_to_ecs_service_doc" {
  statement {
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition"
    ]

    resources = [
      "*"
    ]
  }
}

resource "aws_iam_policy" "update_ecs_service" {
  name        = "DeployToEcsService"
  description = "Allow to update an ECS Servcie"
  policy      = data.aws_iam_policy_document.deploy_to_ecs_service_doc.json
}


resource "aws_iam_user_policy_attachment" "container_registry_power_user" {
  for_each = tomap({
    push_image = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser",
    update_ecs = aws_iam_policy.update_ecs_service.arn
  })

  user       = aws_iam_user.nestjs_notes_github_user.name
  policy_arn = each.value
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

  name               = "nestjs-notes-cluster"
  vpc_id             = module.vpc.vpc_id
  route53_zone_id    = aws_route53_zone.primary.zone_id
  domain_name        = local.domain_name
  public_subnets     = module.vpc.public_subnets
  ecr_repository_url = aws_ecr_repository.nestjs_notes_ecr_repo.repository_url
  DATABASE_URI       = var.DATABASE_URI
}

resource "aws_route53_record" "alb_record" {
  zone_id = aws_route53_zone.primary.zone_id
  # If you're creating a record that has the same name as the hosted zone,
  # don't enter a value (for example, an @ symbol) in the Name field.
  # https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-values-basic.html#rrsets-values-basic-name
  name = ""
  type = "A"

  alias {
    name                   = module.ecs.alb_dns_name
    zone_id                = module.ecs.alb_zone_id
    evaluate_target_health = false
  }
}

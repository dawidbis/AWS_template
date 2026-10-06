terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }

  # State lokalny (terraform.tfstate w tym katalogu) - szybko i bez zależności.
  # Remote state (S3 + use_lockfile) to osobny lab - patrz docs/roadmap.md.
}

provider "aws" {
  # Profil i region z env: AWS_PROFILE / AWS_REGION (ustawia je env.ps1).

  default_tags {
    tags = {
      Project   = local.prefix
      Purpose   = "learning"
      ManagedBy = "terraform"
    }
  }
}

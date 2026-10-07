terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State is local (terraform.tfstate, gitignored) for this homework.
  # For a team, state belongs in a remote backend. See backend.tf.example
  # and the "Terraform state" section of README.md.
}

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Local state for the LocalStack demo (gitignored). For a team on real AWS,
  # use the S3 backend (see backend.tf.example) so state is shared and locked.
}

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# ---------------------------------------------------------------------------
# AWS provider
#
# With use_localstack = true (the default) every AWS API call goes to a
# LocalStack container on http://localhost:4566 with the fake credentials
# "test"/"test". Nothing reaches real AWS and nothing costs money.
#
# To target REAL AWS: set use_localstack = false in terraform.tfvars (which
# drops the endpoints block and the fake keys below) and supply real
# credentials the normal way (aws configure / AWS_PROFILE / env vars).
# Equivalent manual change: delete the endpoints block, the access_key /
# secret_key lines and the skip_* lines.
# ---------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  # Fake demo credentials for LocalStack only. null = use the normal AWS
  # credential chain when talking to real AWS.
  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  # LocalStack has no EC2 metadata service and no real account, so skip
  # these checks there. On real AWS they stay enabled.
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  # http://localhost:4566/<bucket> instead of http://<bucket>.localhost:4566
  s3_use_path_style = var.use_localstack

  # Send each service to LocalStack. Deleting this block (or setting
  # use_localstack = false) makes the provider use the real AWS endpoints.
  dynamic "endpoints" {
    for_each = var.use_localstack ? [var.localstack_endpoint] : []
    content {
      s3       = endpoints.value
      ec2      = endpoints.value
      iam      = endpoints.value
      sts      = endpoints.value
      dynamodb = endpoints.value
    }
  }

  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Owner     = "rudhar-bajaj"
    }
  }
}

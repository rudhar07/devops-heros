# ---------------------------------------------------------------------------
# AWS provider
#
# use_localstack = true (default): every call goes to the LocalStack container
# on http://localhost:4566 with the fake credentials "test"/"test". No real AWS
# account is touched and nothing costs money.
#
# To deploy the SAME code to REAL AWS: set use_localstack = false in
# terraform.tfvars and give real credentials the normal way (aws configure /
# AWS_PROFILE / env vars). That removes the endpoints block and fake keys
# below. Doing it by hand = delete the endpoints block, access_key/secret_key
# and the skip_* lines.
# ---------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style           = var.use_localstack

  # Only present when use_localstack = true. Without it the provider talks to
  # the real *.amazonaws.com endpoints.
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

  # Added to every taggable resource, so each resource block only carries
  # its own Name.
  default_tags {
    tags = {
      Project   = var.project_name
      Session   = "19"
      ManagedBy = "Terraform"
      Owner     = "rudhar-bajaj"
    }
  }
}

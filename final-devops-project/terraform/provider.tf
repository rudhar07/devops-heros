# use_localstack = true  -> every API call goes to LocalStack (fake creds "test").
# use_localstack = false -> real AWS with the normal credential chain
#                           (AWS_PROFILE / aws configure / SSO / env vars).
provider "aws" {
  region = var.aws_region

  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style           = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [var.localstack_endpoint] : []
    content {
      ec2 = endpoints.value
      iam = endpoints.value
      s3  = endpoints.value
      sts = endpoints.value
      ecr = endpoints.value
      eks = endpoints.value
      kms = endpoints.value
    }
  }

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "rudhar-bajaj"
    }
  }
}

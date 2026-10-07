locals {
  common_tags = {
    Name        = var.bucket_name
    Environment = var.environment
    Project     = "Session18"
  }
}

# The bucket itself. force_destroy lets `terraform destroy` empty it first
# (fine for a demo, think twice before using it on real data).
resource "aws_s3_bucket" "demo" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = local.common_tags
}

# Versioning: overwritten/deleted objects keep their old versions.
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Default server-side encryption with S3-managed keys (SSE-S3, AES256).
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block every form of public access (ACLs and bucket policies).
resource "aws_s3_bucket_public_access_block" "demo" {
  bucket = aws_s3_bucket.demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

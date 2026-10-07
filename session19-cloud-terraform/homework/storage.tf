# Bucket for the web server's static assets.
resource "aws_s3_bucket" "assets" {
  bucket        = var.bucket_name
  force_destroy = true # demo only: lets destroy remove a non-empty bucket

  tags = { Name = var.bucket_name }
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The page the instance copies into nginx on boot.
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.assets.id
  key          = "site/index.html"
  content_type = "text/html"
  content      = <<-HTML
    <!doctype html>
    <title>${var.project_name}</title>
    <h1>Session 19: deployed by Terraform</h1>
    <p>VPC ${var.vpc_cidr}, public subnet ${var.public_subnet_cidr}, region ${var.aws_region}.</p>
  HTML
}

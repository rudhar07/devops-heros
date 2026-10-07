variable "use_localstack" {
  description = "true = send all AWS calls to LocalStack (no cost, fake creds). false = real AWS."
  type        = bool
  default     = true
}

variable "localstack_endpoint" {
  description = "LocalStack edge URL, only used when use_localstack = true."
  type        = string
  default     = "http://localhost:4566"
}

variable "aws_region" {
  description = "AWS region where the S3 bucket is created."
  type        = string
  default     = "ap-south-1"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name (3-63 chars, lowercase, digits, hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters of lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Environment name used in tags."
  type        = string
  default     = "dev"
}

variable "enable_versioning" {
  description = "Keep old versions of objects when they are overwritten or deleted."
  type        = bool
  default     = true
}

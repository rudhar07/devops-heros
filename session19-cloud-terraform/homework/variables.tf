variable "use_localstack" {
  description = "true = LocalStack on localhost:4566 (free, fake creds). false = real AWS."
  type        = bool
  default     = true
}

variable "localstack_endpoint" {
  description = "LocalStack edge URL (only used when use_localstack = true)."
  type        = string
  default     = "http://localhost:4566"
}

variable "aws_region" {
  description = "AWS region for every resource."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix for resource names and the Project tag."
  type        = string
  default     = "s19-web"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR such as 10.20.0.0/16."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR of the public subnet (must sit inside vpc_cidr)."
  type        = string
  default     = "10.20.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR of the private subnet (must sit inside vpc_cidr)."
  type        = string
  default     = "10.20.2.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for the web server."
  type        = string
  default     = "t3.micro"
}

variable "ssh_allowed_cidr" {
  description = "Only this CIDR may reach port 22. Never 0.0.0.0/0."
  type        = string
  default     = "203.0.113.10/32" # TEST-NET-3 documentation address, a placeholder

  validation {
    condition     = var.ssh_allowed_cidr != "0.0.0.0/0"
    error_message = "Do not open SSH to the whole internet."
  }
}

variable "bucket_name" {
  description = "Globally unique name for the assets bucket."
  type        = string
}

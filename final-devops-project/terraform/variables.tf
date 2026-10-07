variable "project_name" {
  description = "Prefix for every resource name"
  type        = string
  default     = "taskboard"
}

variable "environment" {
  description = "dev / prod"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "use_localstack" {
  description = "true = talk to LocalStack instead of real AWS"
  type        = bool
  default     = false
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "One public subnet per AZ (load balancers, NAT gateway)"
  type        = list(string)
  default     = ["10.20.101.0/24", "10.20.102.0/24"]
}

variable "private_subnet_cidrs" {
  description = "One private subnet per AZ (EKS worker nodes)"
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "availability_zones" {
  type    = list(string)
  default = ["ap-south-1a", "ap-south-1b"]
}

variable "enable_nat_gateway" {
  description = "Single NAT gateway so private nodes can pull images (costs money on AWS)"
  type        = bool
  default     = true
}

variable "enable_ecr" {
  description = "Create ECR repositories (not emulated by LocalStack community)"
  type        = bool
  default     = true
}

variable "enable_eks" {
  description = "Create the EKS cluster + managed node group (not emulated by LocalStack community)"
  type        = bool
  default     = true
}

variable "eks_version" {
  type    = string
  default = "1.35"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "cluster_endpoint_public_access" {
  description = "Expose the EKS API on the internet. Off by default: use a VPN/bastion, or turn it on together with cluster_admin_cidrs = [\"<your ip>/32\"]."
  type        = bool
  default     = false
}

variable "cluster_admin_cidrs" {
  description = "Who may reach the public EKS API endpoint (only used when cluster_endpoint_public_access = true)"
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

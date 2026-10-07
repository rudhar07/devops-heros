# Values for the local run against LocalStack 4.14.0 community (port 4567).
# EKS and ECR are not emulated by the community edition, so they are off here;
# everything else (VPC, subnets, IGW, NAT, routes, SGs, S3, IAM) is applied.
use_localstack      = true
localstack_endpoint = "http://localhost:4567"
environment         = "dev"
enable_nat_gateway  = true
enable_ecr          = false
enable_eks          = false

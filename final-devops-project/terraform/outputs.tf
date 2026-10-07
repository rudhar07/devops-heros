output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  value = try(aws_nat_gateway.main[0].id, null)
}

output "security_group_ids" {
  value = {
    ingress_lb = aws_security_group.ingress_lb.id
    nodes      = aws_security_group.nodes.id
    database   = aws_security_group.database.id
  }
}

output "artifacts_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}

output "eks_iam_roles" {
  value = {
    cluster = aws_iam_role.eks_cluster.arn
    nodes   = aws_iam_role.eks_nodes.arn
  }
}

output "eks_cluster_name" {
  value = try(aws_eks_cluster.main[0].name, null)
}

output "eks_cluster_endpoint" {
  value = try(aws_eks_cluster.main[0].endpoint, null)
}

output "kubeconfig_command" {
  value = var.enable_eks ? "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.project_name}-${var.environment}" : "EKS disabled (enable_eks = false)"
}

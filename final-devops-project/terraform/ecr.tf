# Private image registry on AWS. CI uses GHCR today; ECR is the AWS-native
# alternative (EKS nodes pull from it with their IAM role, no pull secret).
# Not emulated by LocalStack community -> enable_ecr = false there.
locals {
  ecr_repositories = var.enable_ecr ? toset(["taskboard-backend", "taskboard-frontend"]) : toset([])
}

resource "aws_ecr_repository" "app" {
  for_each             = local.ecr_repositories
  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "IMMUTABLE" # a SHA tag can never be overwritten
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep the last 30 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30 }
      action       = { type = "expire" }
    }]
  })
}

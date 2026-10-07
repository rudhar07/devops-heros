# terraform/ - AWS infrastructure for TaskBoard

```
VPC 10.20.0.0/16 (ap-south-1a, ap-south-1b)
 ├─ public  10.20.101.0/24, 10.20.102.0/24  -> IGW      (load balancers, NAT gateway)
 ├─ private 10.20.1.0/24,   10.20.2.0/24    -> NAT GW   (EKS worker nodes)
 ├─ SGs: ingress-lb (80/443 from internet) -> nodes (NodePorts from LB, node<->node) -> db (5432 from nodes)
 ├─ S3 artifacts bucket (versioned, SSE-S3, public access blocked, old versions expire after 30 days)
 ├─ ECR repositories taskboard/taskboard-{backend,frontend} (immutable tags, scan on push)   [enable_ecr]
 └─ EKS 1.35 (KMS-encrypted Secrets, private API endpoint) + managed node group 2-4 x t3.medium [enable_eks]
     + IAM roles for the control plane and the nodes
```

| Run | Command |
|---|---|
| LocalStack (what I ran) | `terraform init && terraform plan -var-file=localstack.tfvars && terraform apply -var-file=localstack.tfvars && terraform destroy -var-file=localstack.tfvars` |
| Real AWS | `cp terraform.tfvars.example terraform.tfvars`, log in with `aws sso login` / `AWS_PROFILE`, then `terraform init && terraform apply` |

LocalStack 4.14.0 community does not emulate EKS or ECR (`InternalFailure ... not included in your
current license plan`), so `localstack.tfvars` turns those two off. They are still in `terraform plan`
(42 resources with them, 35 without). Full transcript: `../outputs/24-terraform.txt`.

# Security groups. EKS also creates its own cluster SG; these are the extra
# rules this project needs.

# Public entry point: the load balancer in front of ingress-nginx.
resource "aws_security_group" "ingress_lb" {
  name        = "${var.project_name}-${var.environment}-ingress-lb"
  description = "HTTP/HTTPS from the internet to the ingress load balancer"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project_name}-${var.environment}-ingress-lb" }
}

resource "aws_vpc_security_group_ingress_rule" "lb_http" {
  security_group_id = aws_security_group.ingress_lb.id
  description       = "HTTP (redirected to HTTPS by ingress-nginx)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "lb_https" {
  security_group_id = aws_security_group.ingress_lb.id
  description       = "HTTPS"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "lb_to_vpc" {
  security_group_id = aws_security_group.ingress_lb.id
  description       = "Only towards the nodes inside the VPC"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
}

# Worker nodes: reachable only from the LB and from each other.
resource "aws_security_group" "nodes" {
  name        = "${var.project_name}-${var.environment}-nodes"
  description = "EKS worker nodes"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project_name}-${var.environment}-nodes" }
}

resource "aws_vpc_security_group_ingress_rule" "nodes_from_lb" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "NodePorts / ingress-nginx from the load balancer"
  referenced_security_group_id = aws_security_group.ingress_lb.id
  from_port                    = 30000
  to_port                      = 32767
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "nodes_self" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "Pod-to-pod and node-to-node traffic"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "nodes_all" {
  security_group_id = aws_security_group.nodes.id
  description       = "Image pulls, AWS APIs (via NAT)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Database (for a managed RDS PostgreSQL in prod): only nodes may connect.
resource "aws_security_group" "database" {
  name        = "${var.project_name}-${var.environment}-db"
  description = "PostgreSQL from the EKS nodes only"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project_name}-${var.environment}-db" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_nodes" {
  security_group_id            = aws_security_group.database.id
  description                  = "PostgreSQL"
  referenced_security_group_id = aws_security_group.nodes.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

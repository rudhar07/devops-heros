output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet."
  value       = aws_subnet.private.id
}

output "availability_zones_used" {
  description = "AZ of the public and private subnet."
  value       = [aws_subnet.public.availability_zone, aws_subnet.private.availability_zone]
}

output "security_group_id" {
  description = "ID of the web security group."
  value       = aws_security_group.web.id
}

output "ami_id" {
  description = "AMI chosen by the aws_ami data source."
  value       = data.aws_ami.al2023.id
}

output "instance_id" {
  description = "ID of the web server."
  value       = aws_instance.web.id
}

output "instance_public_ip" {
  description = "Public IP of the web server."
  value       = aws_instance.web.public_ip
}

output "instance_private_ip" {
  description = "Private IP of the web server."
  value       = aws_instance.web.private_ip
}

output "assets_bucket" {
  description = "Name of the assets bucket."
  value       = aws_s3_bucket.assets.bucket
}

output "web_url" {
  description = "URL the site would be served on (real AWS only)."
  value       = "http://${aws_instance.web.public_ip}/"
}

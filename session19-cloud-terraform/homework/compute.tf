# Latest Amazon Linux 2023 x86_64 AMI owned by Amazon. Looked up at plan time
# instead of hard-coding an ID, because AMI IDs differ per region.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# --- IAM: let the instance read (only) its own assets bucket ----------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "web" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "read_assets" {
  statement {
    sid       = "ListAssetsBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.assets.arn]
  }
  statement {
    sid       = "ReadAssets"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.assets.arn}/*"]
  }
}

resource "aws_iam_role_policy" "read_assets" {
  name   = "read-assets"
  role   = aws_iam_role.web.id
  policy = data.aws_iam_policy_document.read_assets.json
}

resource "aws_iam_instance_profile" "web" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.web.name
}

# --- The web server ----------------------------------------------------------
resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id        # implicit dependency
  vpc_security_group_ids = [aws_security_group.web.id] # implicit dependency
  iam_instance_profile   = aws_iam_instance_profile.web.name

  # On real AWS this runs once at first boot. It needs the internet (dnf) and
  # the bucket object. LocalStack stores it but does not execute it.
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    aws s3 cp s3://${aws_s3_bucket.assets.bucket}/${aws_s3_object.index.key} /usr/share/nginx/html/index.html
    systemctl enable --now nginx
  EOF

  user_data_replace_on_change = true

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  # EXPLICIT dependency. Nothing in this block references the route table
  # association or the IGW, so without this line Terraform could launch the
  # instance in parallel with (or before) the 0.0.0.0/0 route being attached.
  # The user_data above then runs at first boot with no internet and the
  # dnf install fails, while Terraform still reports success. depends_on
  # forces "route in place first, then instance". It is a dependency on
  # *behaviour*, which references cannot express.
  depends_on = [aws_route_table_association.public]

  tags = { Name = "${var.project_name}-server" }
}

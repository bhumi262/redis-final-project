terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

resource "aws_vpc" "redis_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "redis-project-vpc"
  }
}

resource "aws_subnet" "redis_subnet" {
  vpc_id                  = aws_vpc.redis_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "redis-project-subnet"
  }
}

resource "aws_internet_gateway" "redis_igw" {
  vpc_id = aws_vpc.redis_vpc.id

  tags = {
    Name = "redis-project-igw"
  }
}

resource "aws_route_table" "redis_rt" {
  vpc_id = aws_vpc.redis_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.redis_igw.id
  }

  tags = {
    Name = "redis-project-rt"
  }
}

resource "aws_route_table_association" "redis_rta" {
  subnet_id      = aws_subnet.redis_subnet.id
  route_table_id = aws_route_table.redis_rt.id
}

resource "aws_security_group" "redis_sg" {
  name        = "redis-project-sg"
  description = "Allow SSH and Redis traffic"
  vpc_id      = aws_vpc.redis_vpc.id

  # SSH: Only trusted IPs can connect
  ingress {
    description = "SSH from trusted IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }



  # No public Redis ingress rule.
  # If Flask and Redis run on the same EC2,
  # configure Flask to connect to 127.0.0.1:6379.

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "redis-project-sg"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (official Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}


# IAM role that EC2 will use to connect to SSM
resource "aws_iam_role" "redis_ssm_role" {
  name = "redis-project-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "ec2.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "redis-project-ssm-role"
  }
}

# Permissions required by SSM Agent
resource "aws_iam_role_policy_attachment" "redis_ssm_policy" {
  role = aws_iam_role.redis_ssm_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile attaches the IAM role to EC2
resource "aws_iam_instance_profile" "redis_ssm_profile" {
  name = "redis-project-ssm-profile"
  role = aws_iam_role.redis_ssm_role.name
}


resource "aws_instance" "redis_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = "redis-project-key"
  vpc_security_group_ids      = [aws_security_group.redis_sg.id]
  subnet_id                   = aws_subnet.redis_subnet.id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.redis_ssm_profile.name

  tags = {
    Name = "redis-project-server"
  }
}

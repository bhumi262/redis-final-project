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
   vpc_id      = aws_vpc.redis_vpc.id
  description = "Allow SSH and Redis traffic"

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Redis access"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    description = "Flask app access"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
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

resource "aws_instance" "redis_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = "redis-project-key"
  vpc_security_group_ids = [aws_security_group.redis_sg.id]
   subnet_id              = aws_subnet.redis_subnet.id

  tags = {
    Name = "redis-project-server"
  }
}

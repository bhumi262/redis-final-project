
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

# --------------------------------------------------
# 1. VPC
# --------------------------------------------------
resource "aws_vpc" "redis_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "redis-project-ha-vpc"
  }
}

# --------------------------------------------------
# 2. Public subnet: App + Bastion
# --------------------------------------------------
resource "aws_subnet" "redis_subnet" {
  vpc_id                  = aws_vpc.redis_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "redis-project-ha-public-subnet"
    Tier = "public"
  }
}

# --------------------------------------------------
# 3. Two private subnets in separate AZs
# --------------------------------------------------
resource "aws_subnet" "redis_private_a" {
  vpc_id                  = aws_vpc.redis_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "redis-project-ha-private-subnet-a"
    Tier = "private"
  }
}

resource "aws_subnet" "redis_private_b" {
  vpc_id                  = aws_vpc.redis_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "ap-south-1c"
  map_public_ip_on_launch = false

  tags = {
    Name = "redis-project-ha-private-subnet-b"
    Tier = "private"
  }
}

# --------------------------------------------------
# 4. Internet Gateway for public subnet
# --------------------------------------------------
resource "aws_internet_gateway" "redis_igw" {
  vpc_id = aws_vpc.redis_vpc.id

  tags = {
    Name = "redis-project-ha-igw"
  }
}

resource "aws_route_table" "redis_rt" {
  vpc_id = aws_vpc.redis_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.redis_igw.id
  }

  tags = {
    Name = "redis-project-ha-public-rt"
  }
}

resource "aws_route_table_association" "redis_rta" {
  subnet_id      = aws_subnet.redis_subnet.id
  route_table_id = aws_route_table.redis_rt.id
}

# --------------------------------------------------
# 5. NAT Gateway for private subnet outbound access
# --------------------------------------------------
resource "aws_eip" "redis_nat_eip" {
  domain = "vpc"

  tags = {
    Name = "redis-project-ha-nat-eip"
  }
}

resource "aws_nat_gateway" "redis_nat" {
  allocation_id = aws_eip.redis_nat_eip.id
  subnet_id     = aws_subnet.redis_subnet.id

  depends_on = [aws_internet_gateway.redis_igw]

  tags = {
    Name = "redis-project-ha-nat"
  }
}

resource "aws_route_table" "redis_private_rt" {
  vpc_id = aws_vpc.redis_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.redis_nat.id
  }

  tags = {
    Name = "redis-project-ha-private-rt"
  }
}

resource "aws_route_table_association" "redis_private_rta_a" {
  subnet_id      = aws_subnet.redis_private_a.id
  route_table_id = aws_route_table.redis_private_rt.id
}

resource "aws_route_table_association" "redis_private_rta_b" {
  subnet_id      = aws_subnet.redis_private_b.id
  route_table_id = aws_route_table.redis_private_rt.id
}

# --------------------------------------------------
# 6. Security Group for App + Bastion
# --------------------------------------------------
resource "aws_security_group" "app_sg" {
  name        = "redis-project-ha-app-sg"
  description = "App dashboard and bastion access"
  vpc_id      = aws_vpc.redis_vpc.id

  ingress {
    description = "SSH from trusted client"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "Flask dashboard from trusted client"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = [var.app_allowed_cidr]
  }

  egress {
    description = "Outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "redis-project-ha-app-sg"
  }
}

# --------------------------------------------------
# 7. Security Group for private Redis nodes
# --------------------------------------------------

resource "aws_security_group" "redis_nodes" {
  name        = "redis-project-ha-private-nodes-sg"
  description = "Private Redis and Sentinel access"
  vpc_id      = aws_vpc.redis_vpc.id

  # Port 6379: App server can connect to Redis
  ingress {
    description     = "Redis access from app server"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  # Port 6379: Redis nodes can communicate with each other
  ingress {
    description = "Redis replication between nodes"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    self        = true
  }

  # Port 26379: App server can connect to Sentinel
  ingress {
    description     = "Sentinel access from app server"
    from_port       = 26379
    to_port         = 26379
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  # Port 26379: Sentinel instances can communicate with each other
  ingress {
    description = "Sentinel communication between nodes"
    from_port   = 26379
    to_port     = 26379
    protocol    = "tcp"
    self        = true
  }

  # SSH access only through the app/bastion security group
  ingress {
    description     = "SSH only from app bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  # Allow outbound connections, including package downloads through NAT
  egress {
    description = "Outbound traffic via NAT"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "redis-project-ha-private-nodes-sg"
  }
}


# --------------------------------------------------
# 8. Official Ubuntu 22.04 AMI
# --------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name = "name"
    values = [
      "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
    ]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --------------------------------------------------
# 9. IAM role for EC2 Systems Manager
# --------------------------------------------------
resource "aws_iam_role" "redis_ssm_role" {
  name = "redis-project-ha-ssm-role"

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
    Name = "redis-project-ha-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "redis_ssm_policy" {
  role       = aws_iam_role.redis_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "redis_ssm_profile" {
  name = "redis-project-ha-ssm-profile"
  role = aws_iam_role.redis_ssm_role.name
}

# --------------------------------------------------
# 10. Public EC2: Flask dashboard + bastion
# --------------------------------------------------
resource "aws_instance" "app_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = "redis-project-key"
  subnet_id                   = aws_subnet.redis_subnet.id
  private_ip                  = "10.0.1.10"
  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.app_sg.id
  ]

  iam_instance_profile = aws_iam_instance_profile.redis_ssm_profile.name

  tags = {
    Name = "redis-project-ha-app-server"
    Role = "app-bastion"
  }
}

# --------------------------------------------------
# 11. Private Redis node 1
# Initial intended role: Primary
# --------------------------------------------------
resource "aws_instance" "redis_node_1" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = "redis-project-key"
  subnet_id                   = aws_subnet.redis_private_a.id
  private_ip                  = "10.0.2.10"
  associate_public_ip_address = false

  vpc_security_group_ids = [
    aws_security_group.redis_nodes.id
  ]

  iam_instance_profile = aws_iam_instance_profile.redis_ssm_profile.name

  tags = {
    Name = "redis-project-ha-node-1"
    Role = "redis-primary-candidate"
  }
}

# --------------------------------------------------
# 12. Private Redis node 2
# Initial intended role: Replica
# --------------------------------------------------
resource "aws_instance" "redis_node_2" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = "redis-project-key"
  subnet_id                   = aws_subnet.redis_private_b.id
  private_ip                  = "10.0.3.10"
  associate_public_ip_address = false

  vpc_security_group_ids = [
    aws_security_group.redis_nodes.id
  ]

  iam_instance_profile = aws_iam_instance_profile.redis_ssm_profile.name

  tags = {
    Name = "redis-project-ha-node-2"
    Role = "redis-replica-candidate"
  }
}

# --------------------------------------------------
# 13. Private Redis node 3
# Initial intended role: Replica
# --------------------------------------------------
resource "aws_instance" "redis_node_3" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = "redis-project-key"
  subnet_id                   = aws_subnet.redis_private_a.id
  private_ip                  = "10.0.2.11"
  associate_public_ip_address = false

  vpc_security_group_ids = [
    aws_security_group.redis_nodes.id
  ]

  iam_instance_profile = aws_iam_instance_profile.redis_ssm_profile.name

  tags = {
    Name = "redis-project-ha-node-3"
    Role = "redis-replica-candidate"
  }
}

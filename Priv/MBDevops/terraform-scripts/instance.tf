terraform {

  backend "s3" {
    bucket = "webappuseat1s3bucket"
    key    = "terraform-state"
    region = "ap-south-1"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.33.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

resource "aws_vpc" "vpc-webapp" {
  cidr_block = "10.10.0.0/16"
  tags = {
    Name = "webapp-vpc"
  }
}

resource "aws_internet_gateway" "webapp-igw" {
  vpc_id = aws_vpc.vpc-webapp.id
  tags = {
    Name = "webapp-igw"
  }
}

#EIP for nat gateway
resource "aws_eip" "ip" {
  vpc = true
}

# nat gateway resource
resource "aws_nat_gateway" "webapp-ngw-subnet" {
  allocation_id = aws_eip.ip.id
  subnet_id     = aws_subnet.subnet-webapp-1b.id
}


resource "aws_subnet" "subnet-webapp-1a" {
  vpc_id                  = aws_vpc.vpc-webapp.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = "true"
  tags = {
    Name = "mysubnet-1a"
  }
}

resource "aws_subnet" "subnet-webapp-1b" {
  vpc_id                  = aws_vpc.vpc-webapp.id
  cidr_block              = "10.10.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = "true"
  tags = {
    Name = "mysubnet-1b"
  }
}
#private subnet
resource "aws_subnet" "subnet-webapp-1c" {
  vpc_id            = aws_vpc.vpc-webapp.id
  cidr_block        = "10.10.4.0/24"
  availability_zone = "ap-south-1b"
  tags = {
    Name = "mysubnet-1c"
  }
}

resource "aws_security_group" "webapp-security-grp-allow-port80" {
  name        = "allow_port-80"
  description = "Allow http inbound traffic"
  vpc_id      = aws_vpc.vpc-webapp.id

  ingress {
    description      = "http traffic"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 65535
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name = "allow_http"
  }
}

# bastion host sg
resource "aws_security_group" "webapp-security-grp-bastion-host" {
  name        = "bastion host sg"
  description = "Allow ssh inbound traffic"
  vpc_id      = aws_vpc.vpc-webapp.id

  ingress {
    description      = "bastion host sg"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 65535
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name = "bastion host sg"
  }
}

# sg for private subnet instance only allow bastion host
resource "aws_security_group" "webapp-security-grp-priv-instance" {
  name        = "private host sg"
  description = "Allow bastion ssh inbound traffic"
  vpc_id      = aws_vpc.vpc-webapp.id

  ingress {
    description     = "from bastion host sg"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.webapp-security-grp-bastion-host.id]
  }

  egress {
    description      = "out nat"
    from_port        = 0
    to_port          = 65535
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name = "allow bastion host"
  }
}

# nat gateway route table
resource "aws_route_table" "nat-route" {
  vpc_id = aws_vpc.vpc-webapp.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.webapp-ngw-subnet.id
  }
  tags = {
    Name = "natroute"
  }
}

# private subnet to nat gateway route table association
resource "aws_route_table_association" "natassociate" {
  subnet_id      = aws_subnet.subnet-webapp-1c.id
  route_table_id = aws_route_table.nat-route.id
}

resource "aws_route_table" "webapp-public-route" {
  vpc_id = aws_vpc.vpc-webapp.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.webapp-igw.id
  }
  tags = {
    Name = "webapp-route-table"
  }
}

resource "aws_route_table_association" "webapp-subnet1-rt-assn" {
  subnet_id      = aws_subnet.subnet-webapp-1a.id
  route_table_id = aws_route_table.webapp-public-route.id
}

resource "aws_route_table_association" "webapp-subnet2-rt-assn" {
  subnet_id      = aws_subnet.subnet-webapp-1b.id
  route_table_id = aws_route_table.webapp-public-route.id
}

resource "aws_lb_target_group" "webapp-lb-target-group" {
  name     = "webapp-lb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc-webapp.id
}

variable "custom-AMI" {
  type    = string
  default = "ami-0153ff4de79f1af24"
}

resource "aws_instance" "aws_instance_subnet-1a" {
  ami           = var.custom-AMI
  instance_type = "t2.micro"
  key_name      = "mbkeypairubuntu"
  subnet_id     = aws_subnet.subnet-webapp-1a.id
  vpc_security_group_ids = [
    aws_security_group.webapp-security-grp-allow-port80.id, aws_security_group.webapp-security-grp-bastion-host.id
  ]
  tags = {
    name = "webapp1 public instance subnet1a"
  }
}

resource "aws_instance" "aws_instance_subnet-1b" {
  ami           = var.custom-AMI
  instance_type = "t2.micro"
  key_name      = "mbkeypairubuntu"
  subnet_id     = aws_subnet.subnet-webapp-1b.id
  vpc_security_group_ids = [
    aws_security_group.webapp-security-grp-allow-port80.id, aws_security_group.webapp-security-grp-bastion-host.id
  ]
  tags = {
    name = "webapp2 public instance subnet1b"
  }
}

resource "aws_instance" "aws_instance_subnet-1c" {
  ami           = var.custom-AMI
  instance_type = "t2.micro"
  key_name      = "mbkeypairubuntu"
  subnet_id     = aws_subnet.subnet-webapp-1c.id
  vpc_security_group_ids = [
    aws_security_group.webapp-security-grp-priv-instance.id
  ]
  tags = {
    name = "webapp private instance subnet1c"
  }
}

resource "aws_lb_target_group_attachment" "webapp-instance1-tga" {
  target_group_arn = aws_lb_target_group.webapp-lb-target-group.arn
  target_id        = aws_instance.aws_instance_subnet-1a.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "webapp-instance2-tga" {
  target_group_arn = aws_lb_target_group.webapp-lb-target-group.arn
  target_id        = aws_instance.aws_instance_subnet-1b.id
  port             = 80
}


resource "aws_lb_listener" "webapp-lb-listener" {
  load_balancer_arn = aws_lb.webapp-application-lb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webapp-lb-target-group.arn
  }
}

resource "aws_lb" "webapp-application-lb" {
  name               = "webapp-application-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups = [
    aws_security_group.webapp-security-grp-allow-port80.id, aws_security_group.webapp-security-grp-bastion-host.id
  ]
  subnets = [aws_subnet.subnet-webapp-1a.id, aws_subnet.subnet-webapp-1b.id]

  enable_deletion_protection = false

  tags = {
    Environment = "production"
    Owner       = "MKR"
  }
}

resource "aws_launch_template" "webapp-launch-template" {
  name_prefix   = "webapp-launch-template"
  image_id      = var.custom-AMI
  key_name      = "mbkeypairubuntu"
  instance_type = "t2.micro"
  user_data     = filebase64("ex.sh")
  vpc_security_group_ids = [
    aws_security_group.webapp-security-grp-allow-port80.id, aws_security_group.webapp-security-grp-bastion-host.id
  ]
}

resource "aws_autoscaling_group" "webapp-ASG" {
  vpc_zone_identifier = [aws_subnet.subnet-webapp-1a.id, aws_subnet.subnet-webapp-1b.id]
  desired_capacity    = 2
  max_size            = 3
  min_size            = 2

  launch_template {
    id      = aws_launch_template.webapp-launch-template.id
    version = "$Latest"
  }
}


resource "aws_autoscaling_attachment" "webapp-ASG-attachment" {
  autoscaling_group_name = aws_autoscaling_group.webapp-ASG.id
  lb_target_group_arn   = aws_lb_target_group.webapp-lb-target-group.arn
}





resource "aws_vpc" "myvpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main"
  }
}
resource "aws_subnet" "firstsubnet" {
  vpc_id                  = aws_vpc.myvpc.id
  availability_zone       = "us-east-1a"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
}
resource "aws_subnet" "secondsubnet" {
  vpc_id                  = aws_vpc.myvpc.id
  availability_zone       = "us-east-1b"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}
resource "aws_internet_gateway" "myigw" {
  vpc_id = aws_vpc.myvpc.id
}
resource "aws_route_table" "myroutetable" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myigw.id
  }
}
resource "aws_route_table_association" "associate1" {
  subnet_id      = aws_subnet.firstsubnet.id
  route_table_id = aws_route_table.myroutetable.id
}
resource "aws_route_table_association" "associate2" {
  subnet_id      = aws_subnet.secondsubnet.id
  route_table_id = aws_route_table.myroutetable.id
}
resource "aws_security_group" "name" {
  name   = "allow http"
  vpc_id = aws_vpc.myvpc.id
  tags = {
    Name = "Allow HTTPS"
  }
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_launch_configuration" "as_conf" {
  name_prefix     = "terraform-lc-example-"
  image_id        = data.aws_ami.ubuntu.id
  security_groups = [aws_security_group.name.id]
  instance_type   = "t3.micro"
  user_data       = <<-EOF
              #!/bin/bash
              # Update the system
              apt-get update -y
              apt-get upgrade -y

              # Install Apache HTTP Server
              apt-get install -y apache2

              # Enable Apache to start on boot
              systemctl enable apache2

              # Start Apache service
              systemctl start apache2

              # Create a simple index.html to verify the setup
              echo "<html><body><h1>Welcome to the WebServer-A</h1></body></html>" > /var/www/html/index.html
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "bar" {
  name                 = "terraform-asg-example"
  launch_configuration = aws_launch_configuration.as_conf.name
  min_size             = 1
  desired_capacity     = 2
  max_size             = 3
  vpc_zone_identifier  = [aws_subnet.firstsubnet.id, aws_subnet.secondsubnet.id]

  target_group_arns = [aws_lb_target_group.test.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "mylb" {
  name               = "test-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.name.id]
  subnets            = [aws_subnet.firstsubnet.id, aws_subnet.secondsubnet.id]

  tags = {
    Name = "web"
  }
}
resource "aws_lb_target_group" "test" {
  name     = "tf-example-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.myvpc.id

  health_check {
    path                = "/"
    port                = "traffic-port"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 2

  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.mylb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test.arn
  }
}
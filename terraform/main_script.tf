provider "aws" {
  region = var.region
}
# Create VPC
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  enable_classiclink   = "false"
  instance_tenancy     = "default"
}
# Create Public Subnet for EC2
resource "aws_subnet" "subnet-public-1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = var.AZ1
}
resource "aws_subnet" "subnet-public-2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = var.AZ2
}
# Create Private subnet for RDS
resource "aws_subnet" "subnet-private-1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = "false"
  availability_zone       = var.AZ3
}
# Create second Private subnet for RDS
resource "aws_subnet" "subnet-private-2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.4.0/24"
  map_public_ip_on_launch = "false"
  availability_zone       = var.AZ4
}
# Create IGW for internet connection 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}
# Creating Route table 
resource "aws_route_table" "public-crt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
# Associating route tabe to public subnet
resource "aws_route_table_association" "crta-public-subnet-1" {
  subnet_id      = aws_subnet.subnet-public-1.id
  route_table_id = aws_route_table.public-crt.id
}
resource "aws_route_table_association" "crta-public-subnet-2" {
  subnet_id      = aws_subnet.subnet-public-2.id
  route_table_id = aws_route_table.public-crt.id
}
## Security Group for ELB
resource "aws_security_group" "elb" {
  vpc_id = aws_vpc.vpc.id
  name = "terraform-webserver-elb"
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "MYSQL/Aurora"
    from_port   = 3306
    to_port     = 3306
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
    tags = {
    Name = "allow http,ssh,db"
  }
}
# Security group for RDS
resource "aws_security_group" "RDS_allow_rule" {
  vpc_id = aws_vpc.vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = ["${aws_security_group.elb.id}"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow ec2"
  }
}
# Create RDS Subnet group
resource "aws_db_subnet_group" "RDS_subnet_grp" {
  subnet_ids = ["${aws_subnet.subnet-private-1.id}", "${aws_subnet.subnet-private-2.id}"]
}
# Create RDS instance
resource "aws_db_instance" "wordpressdb" {
  allocated_storage      = 10
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.instance_class
  db_subnet_group_name   = aws_db_subnet_group.RDS_subnet_grp.id
  vpc_security_group_ids = ["${aws_security_group.RDS_allow_rule.id}"]
  name                   = var.database_name
  username               = var.database_user
  password               = var.database_password
  skip_final_snapshot    = true
}
# change USERDATA varible value after grabbing RDS endpoint info
data "template_file" "playbook" {
  template = file("../ansible/roles/copy/tasks/default.yml")
  vars = {
    db_username      = "${var.database_user}"
    db_user_password = "${var.database_password}"
    db_name          = "${var.database_name}"
    db_RDS           = "${aws_db_instance.wordpressdb.endpoint}"
  }
}
# Read ami id just created.
data "aws_ami" "ecs_optimized" {
  most_recent = true
  filter {
    name   = "name"
    values = ["aws-linux-website-wordpess"]
  }
}
resource "aws_key_pair" "mykey-pair" {
  key_name   = "vothanhdo"
  public_key = file(var.PUBLIC_KEY_PATH)
}
# Save Rendered playbook content to local file
resource "local_file" "playbook-rendered-file" {
  content   = "${data.template_file.playbook.rendered}"
  filename  = "../ansible/roles/copy/tasks/main.yml"
}
resource "aws_launch_template" "webserver" {
  name_prefix     = "webserver"
  image_id        = data.aws_ami.ecs_optimized.id
  instance_type   = var.instance_type
  key_name        = aws_key_pair.mykey-pair.id
  vpc_security_group_ids = ["${aws_security_group.elb.id}"]
}
resource "aws_autoscaling_group" "webserver" {
  vpc_zone_identifier = ["${aws_subnet.subnet-public-1.id}", "${aws_subnet.subnet-public-2.id}"]
  name_prefix         = "webserver-asg"
  min_size            = 1
  desired_capacity    = 1
  max_size            = 5
  health_check_type   = "ELB"
  load_balancers = [
    "${aws_elb.webserver-elb.id}"
  ]
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.webserver.id
      }
      override {
        instance_type     = "t2.micro"
        weighted_capacity = "1"
      }
    }
  }
}
### Creating ELB
resource "aws_elb" "webserver-elb" {
  name = "terraform-asg-webserver"
  security_groups       = ["${aws_security_group.elb.id}"]
  subnets               = ["${aws_subnet.subnet-public-1.id}", "${aws_subnet.subnet-public-2.id}"]
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    target              = "HTTP:80/"
  }
  listener {
    lb_port             = 80
    lb_protocol         = "http"
    instance_port       = "80"
    instance_protocol   = "http"
  }
}
data "aws_instances" "test" {
  instance_state_names = ["running"]
  depends_on = [aws_autoscaling_group.webserver]
}
resource "null_resource" "Wordpress_Installation_Waiting" {
  connection {
    type        = "ssh"
    user        = var.USER
    private_key = file(var.PRIV_KEY_PATH)
    host        = data.aws_instances.test.public_ips[0]
  }
# Run script to update python on remote client
  provisioner "remote-exec" {
     inline = ["sudo yum update -y","sudo yum install python3 -y"]
  }
# Play ansible playbook
  provisioner "local-exec" {
     command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ${var.USER} -i '${data.aws_instances.test.public_ips[0]},' --private-key ${var.PRIV_KEY_PATH}  '../ansible/playbook-2.yml'"
  }
}
### Auto scaling policies (Up/Down)
resource "aws_autoscaling_policy" "web_policy_up" {
  name = "web_policy_up"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 180
  autoscaling_group_name = aws_autoscaling_group.webserver.name
}
resource "aws_cloudwatch_metric_alarm" "web_cpu_alarm_up" {
  alarm_name = "web_cpu_alarm_up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "80"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.webserver.name
  }
  alarm_description = "This metric monitor EC2 instance CPU utilization"
  alarm_actions = [ aws_autoscaling_policy.web_policy_up.arn ]
}
resource "aws_autoscaling_policy" "web_policy_down" {
  name = "web_policy_down"
  scaling_adjustment = -1
  adjustment_type = "ChangeInCapacity"
  cooldown = 180
  autoscaling_group_name = aws_autoscaling_group.webserver.name
}
resource "aws_cloudwatch_metric_alarm" "web_cpu_alarm_down" {
  alarm_name = "web_cpu_alarm_down"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "30"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.webserver.name
  }
  alarm_description = "This metric monitor EC2 instance CPU utilization"
  alarm_actions = [ aws_autoscaling_policy.web_policy_down.arn ]
}
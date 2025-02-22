# ------------------------------
# key pair
# ------------------------------
resource "aws_key_pair" "keypair" {
  key_name   = "${var.project}-${var.environment}-keypair"
  public_key = file("~/.ssh/laravel-app-dev-keypair.pub")

  tags = {
    Name    = "${var.project}-${var.environment}-keypair"
    Project = var.project
    Env     = var.environment
  }
}

# ------------------------------
# SSM Parameter Store
# ------------------------------
resource "aws_ssm_parameter" "host" {
  name  = "/${var.project}/${var.environment}/app/MYSQL_HOST"
  type  = "String"
  value = aws_db_instance.mysql_standalone.address
}

resource "aws_ssm_parameter" "port" {
  name  = "/${var.project}/${var.environment}/app/MYSQL_PORT"
  type  = "String"
  value = aws_db_instance.mysql_standalone.port
}

resource "aws_ssm_parameter" "database" {
  name  = "/${var.project}/${var.environment}/app/MYSQL_DATABASE"
  type  = "String"
  value = aws_db_instance.mysql_standalone.name
}

resource "aws_ssm_parameter" "username" {
  name  = "/${var.project}/${var.environment}/app/MYSQL_USERNAME"
  type  = "SecureString"
  value = aws_db_instance.mysql_standalone.username
}

resource "aws_ssm_parameter" "password" {
  name  = "/${var.project}/${var.environment}/app/MYSQL_PASSWORD"
  type  = "SecureString"
  value = random_string.db_password.result
}

resource "aws_ssm_parameter" "s3_access_key_id" {
  name  = "/${var.project}/${var.environment}/app/S3_ACCESS_KEY_ID"
  type  = "SecureString"
  value = var.s3_access_key_id
}

resource "aws_ssm_parameter" "s3_secret_access_key" {
  name  = "/${var.project}/${var.environment}/app/S3_SECRET_ACCESS_KEY"
  type  = "SecureString"
  value = var.s3_secret_access_key
}

resource "aws_ssm_parameter" "github_pat_token" {
  name  = "/${var.project}/${var.environment}/app/GITHUB_PAT_TOKEN"
  type  = "SecureString"
  value = var.github_pat_token
}

# # ------------------------------
# # EC2 Instance
# # ------------------------------
# resource "aws_instance" "app_server" {
#   ami                         = data.aws_ami.app.id
#   instance_type               = "t3.small"
#   subnet_id                   = aws_subnet.public_subnet_1a.id
#   associate_public_ip_address = true
#   iam_instance_profile        = aws_iam_instance_profile.app_ec2_profile.name
#   vpc_security_group_ids = [
#     aws_security_group.app_sg.id,
#     aws_security_group.opmng_sg.id,
#   ]
#   key_name = aws_key_pair.keypair.key_name

#   tags = {
#     Name    = "${var.project}-${var.environment}-app-ec2"
#     Project = var.project
#     Env     = var.environment
#     Type    = "app"
#   }

#   user_data = filebase64("./src/initialize.sh")

#   root_block_device {
#     volume_size = 30 #最低30GB（AmazonLinux2023の制約）
#     volume_type = "gp2"
#   }

#   depends_on = [ aws_db_instance.mysql_standalone ] #RDS完了後にユーザーデータ実行のため
# }

# ------------------------------
# launch template
# ------------------------------
resource "aws_launch_template" "app_lt" {
  update_default_version = true

  name = "${var.project}-${var.environment}-app-lt"

  image_id = data.aws_ami.app.id

  key_name = aws_key_pair.keypair.key_name

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.project}-${var.environment}-app-ec2"
      Project = var.project
      Env     = var.environment
      Type    = "app"
    }
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [
      aws_security_group.app_sg.id,
      aws_security_group.opmng_sg.id,
    ]
    delete_on_termination = true
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.app_ec2_profile.name
  }

  user_data = filebase64("./src/initialize.sh")

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30 # 最低30GB（AmazonLinux2023の制約）
      volume_type = "gp2"
      delete_on_termination = true
    }
  }

  depends_on = [aws_db_instance.mysql_standalone] #RDS完了後にユーザーデータ実行のため
}

# ------------------------------
# auto scaling group
# ------------------------------
resource "aws_autoscaling_group" "app_asg" {
  name = "${var.project}-${var.environment}-app-asg"

  max_size         = 1
  min_size         = 1
  desired_capacity = 1

  health_check_grace_period = 600
  health_check_type         = "ELB"

  vpc_zone_identifier = [
    aws_subnet.public_subnet_1a.id,
    aws_subnet.public_subnet_1c.id
  ]

  target_group_arns = [
    aws_lb_target_group.alb_target_group.arn
  ]

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.app_lt.id
        version            = "$Latest"
      }
      override {
        instance_type = "t3.small"
      }
    }
  }

  depends_on = [aws_db_instance.mysql_standalone] #RDS完了後にユーザーデータ実行のため
}
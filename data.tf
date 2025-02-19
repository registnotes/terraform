data "aws_prefix_list" "s3_pl" {
  name = "com.amazonaws.*.s3"
}

data "aws_ami" "app" {
  most_recent = true
  owners      = ["self", "amazon"]

  #AmazonLinux2023を使用
  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1-x86_64"]
  }
}
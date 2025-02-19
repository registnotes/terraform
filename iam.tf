# ------------------------------
# IAM Role
# ------------------------------
resource "aws_iam_instance_profile" "app_ec2_profile" {
  name = aws_iam_role.app_iam_role.name
  role = aws_iam_role.app_iam_role.name
}

resource "aws_iam_role" "app_iam_role" {
  name               = "${var.project}-${var.environment}-app-iam-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "app_iam_role_ec2_readonly" {
  role       = aws_iam_role.app_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "app_iam_role_ssm_managed" {
  role       = aws_iam_role.app_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "app_iam_role_ssm_readonly" {
  role       = aws_iam_role.app_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "app_iam_role_s3_readonly" {
  role       = aws_iam_role.app_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# ------------------------------
# EC2にRoute53権限付与(Certbot用)
# ------------------------------
data "aws_iam_policy_document" "certbot_route53_policy_document" {
  statement {
    actions = [
      "route53:ListHostedZones",
      "route53:GetChange"
    ]
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "route53:ChangeResourceRecordSets",
    ]
    resources = [
      "arn:aws:route53:::hostedzone/${aws_route53_zone.route53_zone.id}"
    ]
  }
}

resource "aws_iam_policy" "certbot_route53_policy" {
  name        = "CertbotRoute53Policy"
  description = "Policy allowing Certbot to access Route 53 for DNS-01 challenge"
  policy      = data.aws_iam_policy_document.certbot_route53_policy_document.json
}

# Attach Certbot Policy to the Existing IAM Role
resource "aws_iam_role_policy_attachment" "certbot_route53_policy_attachment" {
  role       = aws_iam_role.app_iam_role.name
  policy_arn = aws_iam_policy.certbot_route53_policy.arn
}
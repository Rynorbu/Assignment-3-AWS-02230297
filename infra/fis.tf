# ---------------------------------------------------------------------------
# Assignment 3 – failure test FT3: lose the network of ONE Availability Zone
# for the Lambda (app) subnet, using AWS Fault Injection Service.
# Start it with:  scripts/failure-tests/ft3-az-network-loss.sh
# Cost: $0.10 per action-minute -> a 5-minute run costs about $0.50.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "fis" {
  count = var.enable_fis ? 1 : 0
  name  = "${local.name}-fis"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "fis.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "fis_network" {
  count      = var.enable_fis ? 1 : 0
  role       = aws_iam_role.fis[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorNetworkAccess"
}

resource "aws_fis_experiment_template" "az_network_loss" {
  count       = var.enable_fis ? 1 : 0
  description = "FT3: block all traffic in the ${local.azs[0]} app subnet for 5 minutes"
  role_arn    = aws_iam_role.fis[0].arn

  stop_condition {
    source = "none"
  }

  action {
    name      = "disrupt-app-subnet-az1"
    action_id = "aws:network:disrupt-connectivity"
    parameter {
      key   = "duration"
      value = "PT5M"
    }
    parameter {
      key   = "scope"
      value = "all"
    }
    target {
      key   = "Subnets"
      value = "app-subnet-az1"
    }
  }

  target {
    name           = "app-subnet-az1"
    resource_type  = "aws:ec2:subnet"
    selection_mode = "ALL"
    resource_arns  = [aws_subnet.app[0].arn]
  }

  tags = { Name = "${local.name}-ft3-az-network-loss" }
}

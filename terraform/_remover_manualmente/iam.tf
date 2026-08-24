data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Uma role por lambda. Role compartilhada economizaria linhas de Terraform e
# custaria a capacidade de responder "quem escreveu isso aqui?" no CloudTrail.
resource "aws_iam_role" "lambda" {
  for_each = local.lambdas

  name               = "${var.project}-${each.key}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_lakehouse" {
  statement {
    sid       = "LerLakehouse"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [local.bucket_arn, "${local.bucket_arn}/*"]
  }

  statement {
    sid       = "EscreverCamadasDerivadas"
    actions   = ["s3:PutObject"]
    resources = ["${local.bucket_arn}/*"]
  }

  # Bronze e imutavel para quem TRANSFORMA. A camada crua so pode ser escrita
  # pelo processo de ingestao, que tem role propria. Sem este Deny, um bug de
  # prefixo na silver sobrescreveria a origem e o reprocesso do zero morreria.
  statement {
    sid       = "BronzeImutavel"
    effect    = "Deny"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.bucket_arn}/bronze/*"]
  }
}

resource "aws_iam_role_policy" "lambda_lakehouse" {
  for_each = local.lambdas

  name   = "lakehouse"
  role   = aws_iam_role.lambda[each.key].id
  policy = data.aws_iam_policy_document.lambda_lakehouse.json
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  for_each = local.lambdas

  role       = aws_iam_role.lambda[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------------------------------------------------------
# Step Functions
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = "${var.project}-statemachine-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}

data "aws_iam_policy_document" "sfn" {
  statement {
    sid       = "InvocarLambdasDoPipeline"
    actions   = ["lambda:InvokeFunction"]
    resources = [for f in aws_lambda_function.pipeline : f.arn]
  }

  statement {
    sid       = "NotificarFalha"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid = "Observabilidade"

    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sfn" {
  name   = "pipeline"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn.json
}

# ---------------------------------------------------------------------------
# EventBridge Scheduler
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.project}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

resource "aws_iam_role_policy" "scheduler" {
  name = "disparar-pipeline"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = aws_sfn_state_machine.pipeline.arn
    }]
  })
}

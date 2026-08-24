resource "aws_cloudwatch_log_group" "lambda" {
  for_each = local.lambdas

  name              = "/aws/lambda/${var.project}-${each.key}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "pipeline" {
  for_each = local.lambdas

  function_name = "${var.project}-${each.key}"
  description   = each.value.description
  role          = aws_iam_role.lambda[each.key].arn
  handler       = "handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = each.value.timeout
  memory_size   = each.value.memory
  layers        = [var.pandas_layer_arn]

  filename         = "${var.artifacts_dir}/flutter-${each.key}.zip"
  source_code_hash = filebase64sha256("${var.artifacts_dir}/flutter-${each.key}.zip")

  environment {
    variables = each.value.environment
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_logs,
  ]
}

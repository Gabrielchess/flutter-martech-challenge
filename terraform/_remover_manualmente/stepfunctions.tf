resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/vendedlogs/states/${var.project}-pipeline"
  retention_in_days = var.log_retention_days
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${var.project}-pipeline"
  role_arn = aws_iam_role.sfn.arn

  definition = templatefile("${path.module}/statemachine.asl.tftpl", {
    project       = var.project
    fx_arn        = aws_lambda_function.pipeline["fx"].arn
    silver_arn    = aws_lambda_function.pipeline["silver"].arn
    gold_arn      = aws_lambda_function.pipeline["gold"].arn
    sns_topic_arn = aws_sns_topic.alerts.arn
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }
}

resource "aws_scheduler_schedule" "pipeline" {
  name       = "${var.project}-mensal"
  state      = var.schedule_enabled ? "ENABLED" : "DISABLED"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_sfn_state_machine.pipeline.arn
    role_arn = aws_iam_role.scheduler.arn

    # ingest_date fica de fora de proposito: a lambda usa a data de hoje
    # quando ela nao vem. Fixar aqui congelaria a particao de bronze.
    input = jsonencode({
      reference_date = var.reference_date
    })

    retry_policy {
      maximum_retry_attempts       = 0
      maximum_event_age_in_seconds = 3600
    }
  }
}

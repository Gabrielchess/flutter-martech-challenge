# O pipeline falhou por completo. E o alarme que nunca pode faltar: sem ele,
# ninguem descobre que a gold parou ate alguem abrir um relatorio vazio.
resource "aws_cloudwatch_metric_alarm" "pipeline_failed" {
  alarm_name          = "${var.project}-pipeline-falhou"
  alarm_description   = "Alguma execucao do Step Functions terminou em FAILED"
  namespace           = "AWS/States"
  metric_name         = "ExecutionsFailed"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.pipeline.arn
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# Violacao de contrato ERROR. Diferente do alarme acima: aqui o pipeline pode
# ate ter rodado, mas o dado reprovou o contrato. Metrica vem do EMF emitido
# pelas proprias lambdas.
resource "aws_cloudwatch_metric_alarm" "dq_error" {
  for_each = toset(["silver", "gold"])

  alarm_name          = "${var.project}-dq-error-${each.key}"
  alarm_description   = "Check de Data Quality com severidade ERROR reprovou na camada ${each.key}"
  namespace           = "FlutterMartech/DataQuality"
  metric_name         = "ChecksFailedError"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Layer = each.key
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# Cambio em modo degradado: a lambda usou a ultima cotacao conhecida porque a
# Frankfurter nao respondeu. Nao derruba o pipeline, mas o numero envelhece.
resource "aws_cloudwatch_metric_alarm" "fx_degradado" {
  alarm_name          = "${var.project}-cambio-degradado"
  alarm_description   = "A ingestao de cambio caiu em modo degradado"
  namespace           = "FlutterMartech/DataQuality"
  metric_name         = "DegradedMode"
  statistic           = "Maximum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Layer = "reference"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = var.project

  dashboard_body = jsonencode({
    start = "-P7D"
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Execucoes do pipeline"
          region = var.region
          stat   = "Sum"
          period = 3600
          view   = "timeSeries"
          metrics = [
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", aws_sfn_state_machine.pipeline.arn],
            [".", "ExecutionsFailed", ".", "."],
            [".", "ExecutionsTimedOut", ".", "."],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Data Quality por camada — ERROR e WARN"
          region = var.region
          stat   = "Sum"
          period = 3600
          view   = "timeSeries"
          metrics = [
            ["FlutterMartech/DataQuality", "ChecksFailedError", "Layer", "silver"],
            [".", "ChecksFailedWarn", ".", "."],
            [".", "ChecksFailedError", ".", "gold"],
            [".", "ChecksFailedWarn", ".", "."],
          ]
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 8
        properties = {
          title  = "Por entidade — lidas, gravadas em silver, quarentenadas"
          region = var.region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.lambda["silver"].name}' | fields @timestamp, ingest_date, Entity, RowsIngested, RowCount, RowsQuarantined, ChecksTotal, DuplicateKeys, BlankValues, FormatViolations, OutOfRangeNumerics, FutureDatedRecords, ProcessingDurationMs\n| filter ispresent(Entity)\n| sort @timestamp desc\n| limit 30"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 14
        width  = 24
        height = 8
        properties = {
          title  = "Imperfeicoes por coluna — passed=0 significa tolerancia do contrato estourada"
          region = var.region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.lambda["silver"].name}' | SOURCE '${aws_cloudwatch_log_group.lambda["gold"].name}' | fields @timestamp, entity, column, check, severity, failed_records, failed_ratio, passed, details\n| filter dq_check = 1\n| sort @timestamp desc, failed_records desc\n| limit 30"
        }
      },
    ]
  })
}

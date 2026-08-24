output "dashboard_name" {
  value = aws_cloudwatch_dashboard.this.dashboard_name
}

output "alarm_names" {
  value = concat(
    [aws_cloudwatch_metric_alarm.pipeline_failed.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.dq_error : a.alarm_name],
    [aws_cloudwatch_metric_alarm.fx_degradado.alarm_name],
  )
}

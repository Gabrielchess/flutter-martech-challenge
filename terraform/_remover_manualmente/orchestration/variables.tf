variable "project" {
  type = string
}

variable "lambda_arns" {
  description = "Mapa camada -> ARN da lambda. Espera as chaves fx, silver e gold."
  type        = map(string)
}

variable "reference_date" {
  type = string
}

variable "schedule_expression" {
  type = string
}

variable "schedule_enabled" {
  type    = bool
  default = false
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "state_machine_arn" {
  type = string
}

variable "log_group_names" {
  description = "Mapa camada -> nome do log group"
  type        = map(string)
}

variable "alarm_actions" {
  description = "Vazio = alarme existe e fica vermelho no console, mas nao avisa ninguem"
  type        = list(string)
  default     = []
}

variable "dq_namespace" {
  description = "Namespace EMF emitido pelas lambdas (shared/logger.py)"
  type        = string
  default     = "FlutterMartech/DataQuality"
}

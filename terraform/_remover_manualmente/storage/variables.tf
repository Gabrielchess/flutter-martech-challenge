variable "bucket_name" {
  type = string
}

variable "athena_results_ttl" {
  description = "Dias ate expirar resultado de query do Athena"
  type        = number
  default     = 7
}

variable "noncurrent_days" {
  description = "Dias ate expirar versao antiga de objeto"
  type        = number
  default     = 30
}

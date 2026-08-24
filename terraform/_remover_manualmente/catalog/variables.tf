variable "database_name" {
  type = string
}

variable "workgroup_name" {
  type = string
}

variable "output_location" {
  description = "s3://.../athena-results/"
  type        = string
}

variable "bytes_scanned_cutoff" {
  description = <<-EOT
    Teto de scan por query. O dataset tem 250 jogadores; qualquer query que
    passe de 1 GB e cross join acidental, nao analise.
  EOT
  type        = number
  default     = 1073741824
}

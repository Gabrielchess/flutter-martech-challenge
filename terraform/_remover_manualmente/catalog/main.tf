resource "aws_glue_catalog_database" "this" {
  name        = var.database_name
  description = "Catalogo das camadas silver e gold do lakehouse Martech"
}

resource "aws_athena_workgroup" "this" {
  name = var.workgroup_name

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.bytes_scanned_cutoff

    result_configuration {
      output_location = var.output_location

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  force_destroy = true
}

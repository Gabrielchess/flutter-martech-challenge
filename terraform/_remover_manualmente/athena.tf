resource "aws_glue_catalog_database" "martech" {
  name        = var.glue_database
  description = "Catalogo das camadas silver e gold do lakehouse Martech"
}

resource "aws_athena_workgroup" "martech" {
  name = var.project

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.lakehouse.bucket}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    # Teto por query. O dataset e minusculo; qualquer query que passe disso e
    # cross join acidental, nao analise.
    bytes_scanned_cutoff_per_query = 1073741824
  }

  force_destroy = true
}

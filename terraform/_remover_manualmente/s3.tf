resource "aws_s3_bucket" "lakehouse" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "lakehouse" {
  bucket                  = aws_s3_bucket.lakehouse.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versionamento e a rede de seguranca do overwrite: silver e gold sao gravadas
# como PutObject idempotente, entao uma execucao ruim sobrescreve a boa.
resource "aws_s3_bucket_versioning" "lakehouse" {
  bucket = aws_s3_bucket.lakehouse.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lakehouse" {
  bucket = aws_s3_bucket.lakehouse.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lakehouse" {
  bucket     = aws_s3_bucket.lakehouse.id
  depends_on = [aws_s3_bucket_versioning.lakehouse]

  rule {
    id     = "expirar-resultados-athena"
    status = "Enabled"

    filter {
      prefix = "athena-results/"
    }

    expiration {
      days = 7
    }
  }

  rule {
    id     = "limitar-versoes-antigas"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

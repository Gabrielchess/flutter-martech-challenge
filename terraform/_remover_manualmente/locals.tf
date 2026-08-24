locals {
  account_id = data.aws_caller_identity.current.account_id
  bucket_arn = aws_s3_bucket.lakehouse.arn

  lambdas = {
    fx = {
      description = "Ingere cotacoes do BCE via Frankfurter e materializa a tabela densa de cambio"
      timeout     = 300
      memory      = 512
      environment = {
        LAKEHOUSE_BUCKET    = var.bucket_name
        FX_QUOTE_CURRENCIES = "USD,EUR"
        FX_START_DATE       = "2023-07-25"
        DQ_REFERENCE_DATE   = var.reference_date
      }
    }
    silver = {
      description = "bronze -> silver: valida, deduplica, quarentena, tipa e converte para BRL"
      timeout     = 300
      memory      = 1024
      environment = {
        LAKEHOUSE_BUCKET  = var.bucket_name
        DQ_REFERENCE_DATE = var.reference_date
        DQ_FAIL_ON_ERROR  = "true"
      }
    }
    gold = {
      description = "silver -> gold: star schema com 3 dimensoes e 3 fatos"
      timeout     = 300
      memory      = 1024
      environment = {
        LAKEHOUSE_BUCKET = var.bucket_name
        REFERENCE_DATE   = var.reference_date
        DQ_FAIL_ON_ERROR = "true"
      }
    }
  }
}

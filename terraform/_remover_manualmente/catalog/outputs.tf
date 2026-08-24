output "database_name" {
  value = aws_glue_catalog_database.this.name
}

output "workgroup_name" {
  value = aws_athena_workgroup.this.name
}

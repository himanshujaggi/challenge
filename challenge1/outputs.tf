output "SERVER_NAME" {
  value       = google_sql_database.database.name
  description = "name of the database created"
}
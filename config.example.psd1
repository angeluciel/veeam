@{
  # Veeam
  VeeamBaseUrl      = "https://localhost:9443"
  ApiVersion        = "1.3-rev1"
  PathToCredential  = "C:\VeeamInventory\credentials.clixml"

  # Backup Evaluation
  MaxHoursBackup    = 36

  # Payload
  SchemaVersion     = "1"
  ClientName        = "example-client"
  ClientDisplayName = "Example Client"

  # n8n
  N8NUri            = "https://n8n.example.com/webhook/veeam"

  # Logging
  LogDirectory      = "C:\VeeamInventory\logs"
  LogLevel          = "INFO"
  LogRetentionDays  = 30
}
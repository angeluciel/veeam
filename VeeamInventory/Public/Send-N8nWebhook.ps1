function Send-N8nWebhook {
    param(
        [Parameter(Mandatory)][string] $WebhookUri,
        [Parameter(Mandatory)][pscustomobject] $Payload,
        [Parameter(Mandatory)] $headers
    )
    
    Write-Log "Enviando para n8n" -Level INFO -Context 'N8N'

    try {
        $Json = $Payload | ConvertTo-Json -Depth 15

        Write-Log "Enviando payload para n8n..." -Level INFO -Context 'N8N'
        Write-Log "URI: $WebhookUri" -Level DEBUG -Context 'N8N'

        $PostResponse = Invoke-RestMethod `
            -Uri            $WebhookUri `
            -Method         POST `
            -ContentType    'application/json' `
            -Headers @{ 'x-api-key' = $headers }`
            -Body           $Json `
            -SkipCertificateCheck

        Write-Log "Envio para n8n concluido com sucesso" -Level SUCCESS -Context 'N8N'
        Write-Log "Resposta: $($PostResponse | ConvertTo-Json -Depth 15)" -Level DEBUG -Context 'N8N'
        return $true
    }
    catch {
        Write-Log "Falha ao enviar para n8n: $_" -Level ERROR -Context 'N8N'
        if ($_.ErrorDetails.Message) { Write-Log "Body: $($_.ErrorDetails.Message)" -Level ERROR -Context 'N8N' }
        return $false
    }
}
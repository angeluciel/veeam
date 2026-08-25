function Get-Hosts {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][hashtable]$headers
    )

    Write-Log "Consultando hosts do inventário." -Level INFO -Context 'INVENT'

    try {
        $response = Invoke-RestMethod `
                -Method 'Post'`
                -Uri "$BaseUrl/api/v1/inventory" `
                -Headers  $Headers `
                -ContentType 'application/json' `
                -SkipCertificateCheck

        $allEntries = @($response.data)
        $hosts = @($allEntries | Where-Object {
            $_.PSObject.Properties['type'] -and $_.type -eq 'Host'
            })

        Write-Log ($hosts | Format-Table hostName, platform, objectId | Out-String) -Level DEBUG -Context 'INVENT'
        Write-Log "Hosts detectados: $($hosts.Count)" -Level INFO -Context 'INVENT'

        if ($hosts.Count -eq 0) {
            $msg = "Nenhum host do tipo 'Host' foi retornado pelo inventário."
            Write-Log $msg -Level ERROR -Context 'INVENT'
            throw $msg
        }

        return $hosts
    }
    catch {
        $msg = "Falha ao consultar os hosts do inventário: $($_.Exception.Message)"
        Write-Log $msg -Level ERROR -Context 'INVENT'
        throw $msg
    }
}
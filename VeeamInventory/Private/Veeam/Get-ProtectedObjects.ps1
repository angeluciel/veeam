function Get-ProtectedObjects {
    
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][hashtable]$headers
    )

    Write-Log "Consultando objetos do catálogo de backup" -Level INFO -Context "PROTECT"

    try {
        $all = @()
        $skip = 0
        $limit = 200
        $page = 0

        do {
            $page++
            $resp = Invoke-RestMethod `
                -Method Get `
                -Uri "$BaseUrl/api/v1/backupObjects?limit=$limit&skip=$skip" `
                -Headers $headers `
                -SkipCertificateCheck

            $pageData = @($resp.data)
            $all += $pageData
            $total = [int]$resp.pagination.total
            $skip += $limit

            Write-Log "Pagina $page`: $($pageData.Count) objeto(s); acumulado $($all.Count)/$total" -Level INFO -Context "PROTECT"
        } while ($skip -lt $total)

        Write-Log "Objetos encontrados no catalogo: $($all.Count)" -Level SUCCESS -Context "PROTECT"

        return $all
    }
    catch {
        $msg = "Falha ao consular os objetos do catálogo de backup: $($_.Exception.Message)"
        Write-Log $msg -Level ERROR -Context "PROTECT"
        throw $msg
    }
}
function Get-BackupCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][array]$Objects,
        [string]$Context = 'RP'
    )

    $objectCount = @($Objects).Count

    Write-Log `
        "Consultando o restore point mais recente de $objectCount objeto(s)" `
        -Level INFO `
        -Context $Context

    $catalogo = @{}
    $semPontos = 0
    $falhas = 0
    $invalidos = 0
    $comRestorePoint = 0
    $i = 0

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($obj in @($Objects)) {
        $i++

        if ($i % 25 -eq 0) {
            Write-Log `
                "Progresso: $i/$objectCount" `
                -Level INFO `
                -Context $Context
        }

        if ($null -eq $obj) {
            $invalidos++

            Write-Log `
                "Objeto nulo encontrado na posição $i; registro ignorado" `
                -Level WARN `
                -Context $Context

            continue
        }

        $objectId = [string]$obj.id
        $rawName = [string]$obj.name

        if (
            [string]::IsNullOrWhiteSpace($objectId) -or
            [string]::IsNullOrWhiteSpace($rawName)
        ) {
            $invalidos++

            $objectDebug = $obj | ConvertTo-Json -Depth 4 -Compress

            Write-Log `
                "Objeto inválido na posição $i`: id ou name ausente. Objeto: $objectDebug" `
                -Level WARN `
                -Context $Context

            continue
        }

        $nome = $rawName.Trim()
        $escapedObjectId = [uri]::EscapeDataString($objectId)

        try {
            $rp = Invoke-RestMethod `
                -Method Get `
                -Uri "$BaseUrl/api/v1/backupObjects/$escapedObjectId/restorePoints?limit=1&orderColumn=CreationTime&orderAsc=false" `
                -Headers $Headers `
                -SkipCertificateCheck

            if (-not $rp.data -or @($rp.data).Count -eq 0) {
                $semPontos++

                Write-Log `
                    "'$nome' está no catálogo, mas não possui restore point" `
                    -Level WARN `
                    -Context $Context

                continue
            }

            $creationTime = [string]$rp.data[0].creationTime
            [DateTimeOffset]$data = [DateTimeOffset]::MinValue

            $parsed = [DateTimeOffset]::TryParse(
                $creationTime,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind,
                [ref]$data
            )

            if (-not $parsed) {
                $msg = "creatonTime inválido para '$nome': '$creationTime'"
                Write-Log $msg -Level ERROR -Context 'RP'
                throw $msg
            }

            $comRestorePoint++

            if ($catalogo.ContainsKey($nome)) {
                if ($data -le $catalogo[$nome].LastBackup) {
                    Write-Log `
                        "'$nome' duplicado: mantendo a cadeia mais recente" `
                        -Level DEBUG `
                        -Context $Context

                    continue
                }

                Write-Log `
                    "'$nome' duplicado: substituindo pela cadeia mais recente" `
                    -Level DEBUG `
                    -Context $Context
            }

            $catalogo[$nome] = [PSCustomObject]@{
                LastBackup = $data.ToUniversalTime()
                Plataform = $obj.platformName
                Tipo       = $obj.type
                Points     = $obj.restorePointsCount
                ObjectId   = $objectId
            }
        }
        catch {
            $falhas++

            Write-Log `
                "Falha ao processar '$nome' ($objectId): $($_.Exception.Message)" `
                -Level ERROR `
                -Context $Context
        }
    }

    $sw.Stop()

    $duplicatas = $comRestorePoint - $catalogo.Count

    Write-Log `
        "Catálogo montado: $($catalogo.Count) VM(s) com restore point em $([math]::Round($sw.Elapsed.TotalSeconds, 1))s" `
        -Level SUCCESS `
        -Context $Context

    if ($duplicatas -gt 0) {
        Write-Log `
            "$duplicatas cadeia(s) duplicada(s) descartada(s)" `
            -Level WARN `
            -Context $Context
    }

    if ($semPontos -gt 0) {
        Write-Log `
            "$semPontos objeto(s) sem restore point" `
            -Level WARN `
            -Context $Context
    }

    if ($invalidos -gt 0) {
        Write-Log `
            "$invalidos objeto(s) inválido(s) ignorado(s)" `
            -Level WARN `
            -Context $Context
    }

    if ($falhas -gt 0) {
        Write-Log `
            "$falhas objeto(s) apresentaram erro durante o processamento" `
            -Level ERROR `
            -Context $Context
    }

    return $catalogo
}
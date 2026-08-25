function Get-VeeamJobs {
    <#
    .SYNOPSIS
    Consulta e retorna todos os jobs do Veeam
    #>
    param(
        [string]$BaseUrl,
        [hashtable]$Headers
    )
    
    Write-Log "Consultando Jobs..." -Level INFO -Context 'JOBS'

    try {
        $JobsUri = "$BaseUrl/api/v1/jobs"

        $JobsResponse = Invoke-RestMethod `
            -Uri            $JobsUri `
            -Method         GET `
            -Headers        $Headers `
            -SkipCertificateCheck

        $Jobs = $JobsResponse.data
        Write-Log "Foram retornados: $($Jobs.Count) jobs" -Level SUCCESS -Context 'JOBS'

        return $Jobs
    }
    catch {
        Write-Log "Falha ao consultar jobs: $_" -Level ERROR -Context 'JOBS'
        exit 1
    }
}
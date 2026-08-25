function Get-VeeamRepositories {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers
    )
    
    Write-Log "Consultando Repositórios..." -Level INFO -Context 'REPO'

    $RepositoryMap = @{}
    $AllRepositories = @()

    $RepositoryPaths = @(
        "/repositories",
        "/scaleOutRepositories"
    )

    foreach ($path in $RepositoryPaths) {
        try {
            $RepositoriesUri = "$BaseUrl/api/v1/backupInfrastructure$path"
            Write-Log "Consultando: $path" -Level DEBUG -Context 'REPO'

            $RepositoriesResponse = Invoke-RestMethod `
                -Uri     $RepositoriesUri `
                -Method  GET `
                -Headers $Headers `
                -SkipCertificateCheck

            $Repositories = $RepositoriesResponse.data
            if ($Repositories) {
                Write-Log "Encontrados: $($Repositories.Count) repositório(s)" -Level SUCCESS -Context 'REPO'

                $AllRepositories += $Repositories
                foreach ($repo in $Repositories) {
                    $RepositoryMap[$repo.id] = @{
                        name = $repo.name
                        path = $path
                    }
                }
            }
        }
        catch {
            Write-Log "Nenhum repositório em $path ou erro: $_" -Level WARN -Context 'REPO'
        }
    }

    if ($AllRepositories.Count -eq 0) {
        Write-Log "Nenhum repositório encontrado" -Level WARN -Context 'REPO'
    }
    else {
        Write-Log "Total de $($AllRepositories.Count) repositórios encontrados" -Level SUCCESS -Context 'REPO'
    }
    
    return $RepositoryMap
}
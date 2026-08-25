function Get-RepositoryNameFromId {
    <#
    .SYNOPSIS
    Retorna o nome do repositório a partir do ID
    #>
    param(
        [string]$RepositoryId,
        [hashtable]$RepositoryMap
    )
    
    if ($RepositoryId -and $RepositoryMap.ContainsKey($RepositoryId)) {
        return $RepositoryMap[$RepositoryId].name
    }
    return "N/A"
}
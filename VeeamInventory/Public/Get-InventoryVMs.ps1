function Get-InventoryVMs {
    param(
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][string]$BaseUrl
    )

    $hosts = Get-Hosts -Headers $Headers -BaseUrl $BaseUrl
    $vms = @(Get-VMs -Headers $Headers -Hosts $hosts -BaseUrl $BaseUrl)

    if ($vms.Count -eq 0) {
        $msg = "Nenhuma VM foi encontrada, hosts acessíveis."
        Write-Log $msg -Level WARN -Context "INVENT"
        throw $msg
    }

    $duplicates = @($vms | Group-Object VMName | Where-Object Count -gt 1)
    foreach ($duplicate in $duplicates) {
        Write-Log "A VM '$(duplicate.Name)' aparece em $($duplicate.Count) hosts: $($duplicate.Group.Host -join ', '). Ela será avaliada uma vez." -Level WARN -Context "INVENT"
    }
    $uniqueCount = @($vms | Select-Object -ExpandProperty VMName -Unique).Count
    Write-Log "VMs unicas no inventario: $uniqueCount" -Level INFO -Context "INVENT"

    return $vms
}
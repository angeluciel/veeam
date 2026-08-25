function Get-VMs {
    param(
        [Parameter (Mandatory)] [string]$BaseUrl,
        [Parameter (Mandatory)] [hashtable]$Headers,
        [Parameter (Mandatory)] [Object[]]$Hosts,
        [int]$ThrottleLimit = 4
    )

    Write-Log "Consultandos VMs de $($Hosts.Count) host(s)" -Level INFO -Context 'VMs'

    $failureBag = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

    $vms = $Hosts | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        $hs = $_
        $headers = $using:Headers
        $baseUrl = $using:BaseUrl
        $failureBag = $using:failureBag

        try {
            $escapedHostName = [uri]::EscapeDataString($hs.hostName)
            $uri = "$baseUrl/api/v1/inventory/$escapedHostName" + "?typeFilter=VirtualMachine"

            $response = Invoke-RestMethod -Method Post -Uri $uri `
                -ContentType "application/json" `
                -Headers $headers `
                -SkipCertificateCheck `
                -ErrorAction Stop

            foreach ($vm in $response.data) {
                [PSCustomObject]@{
                    Host     = $hs.hostName
                    VMName   = $vm.name
                    ObjectId = if ($vm.PSObject.Properties['objectId']) { $vm.objectId } else { $null }
                    Platform = if ($vm.PSObject.Properties['platform']) { $vm.platform } else { $null }
                    Size     = if ($vm.PSObject.Properties['size']) { $vm.size } else { $null }
                }
            }
        }
        catch {
            $failureBag.Add($hs.hostName)
        }
    }

    if ($failureBag.Count -gt 0) {
            $failedHosts = @($failureBag | Sort-Object -Unique)
            $msg = "Inventário incompleto. Falha ao consultar: $($failedHosts -join ', ')."
            Write-Log $msg -Level ERROR -Context 'VMs'
            throw $msg
        }

        Write-Log "VMs detectadas: $(@($vms).Count)" -Level SUCCESS -Context 'VMs'
        return $vms

}

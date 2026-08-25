function ConvertTo-JobObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Jobs,
        [hashtable]$RepositoryMap = @{},
        [int]$Throttle = 5,
        [string]$BaseUrl,
        [hashtable]$Headers
    )

    $data = if ($Jobs -is [string]) { $Jobs | ConvertFrom-Json } else { $Jobs }

    if (-not (Test-Path function:Get-RepositoryNameFromId)) {
        throw "Get-RepositoryNameFromId not loaded."
    }
    $repoFnDef = ${function:Get-RepositoryNameFromId}.ToString()

    # O runspace paralelo nao herda o estado de modulo do PSLogging, entao as
    # mensagens sao enfileiradas aqui e reproduzidas no runspace principal.
    $logQueue = [System.Collections.Concurrent.ConcurrentQueue[pscustomobject]]::new()

    $results = $data | ForEach-Object -ThrottleLimit $throttle -Parallel {
        $job = $_
        $repoMap = $using:RepositoryMap
        $baseUrl = $using:BaseUrl
        $headers = $using:Headers
        $logQueue = $using:logQueue
        ${function:Get-RepositoryNameFromId} = $using:repoFnDef

        function ConvertTo-IsoWeekday([Parameter(Mandatory)][string]$day) {
                
                $dayOfWeek = [System.Enum]::Parse(
                    [System.DayOfWeek],
                    $day,
                    $true
                )
                (([int] $dayOfWeek + 6) % 7) + 1
            }

        function Format-FullPolicy($policy) {

            if (-not $policy -or -not $policy.isEnabled) {
                return $null
            }

            $ordinal = @{
                First = 1
                Second = 2
                Third = 3
                Fourth = 4
                Last = -1
            }

            $weekly = if ($policy.weekly.isEnabled) {
                [pscustomobject]@{
                    daysOfWeek = @(
                        $policy.weekly.days | ForEach-Object { ConvertTo-IsoWeekday $_ }
                    )
                }
            }
            else { $null }

            $monthly = if ($policy.monthly.isEnabled) {
                $rule = if ($policy.monthly.isLastDayOfMonth) {
                    [pscustomobject]@{
                        kind = 'last-day'
                    }
                }
                else {
                    [pscustomobject]@{
                        kind       = 'nth-weekday'
                        occurrence = [int] $ordinal[$policy.monthly.dayNumberInMonth]
                        dayOfWeek  = ConvertTo-IsoWeekday $policy.monthly.dayOfWeek
                    }
                }

                [pscustomobject]@{
                    months = @($policy.monthly.months)
                    rule = $rule
                }
            }
            else { $null }


            return [pscustomobject]@{
                weekly = $weekly
                monthly = $monthly
            }
        }

        function Format-GfsPolicy($gfs) {

            if (-not $gfs -or -not $gfs.isEnabled) { return $null }

            return [pscustomobject]@{
                weekly  = if ($gfs.weekly.isEnabled){
                    [pscustomobject]@{
                        keepForWeeks = [int] $gfs.weekly.keepForNumberOfWeeks
                        dayOfWeek    = ConvertTo-IsoWeekday $Gfs.weekly.desiredTime
                    }
                }
                else { $null }

                monthly = if ($gfs.monthly.isEnabled) {
                    [pscustomobject]@{
                        keepForMonths = [int] $gfs.monthly.keepForNumberOfMonths
                        weekOfMonth   = [string] $Gfs.monthly.desiredTime
                    }
                }
                else { $null }

                yearly  = if ($gfs.yearly.isEnabled) {
                    [pscustomobject]@{
                        keepForYears = [int] $gfs.yearly.keepForNumberOfYears
                        month        = [string] $gfs.yearly.desiredTime
                    }
                }
                else { $null }

            }
        }

        function Format-Schedule($job) {

            $schedule = $job.schedule
            $ordinal = @{
                First = 1
                Second = 2
                Third = 3
                Fourth = 4
                Last = -1
            }

            if (-not $schedule.runAutomatically) {
                return [pscustomobject]@{
                    kind = 'manual'
                }
            }

            if ($schedule.daily.isEnabled) {
                return [pscustomobject]@{
                    kind = 'daily'
                    mode = [string] $schedule.daily.dailyKind
                    localTime = [string] $schedule.daily.localTime
                    dayOfWeek = @(
                        $schedule.daily.days | ForEach-Object { ConvertTo-IsoWeekday $_ }
                    )
                }
            }

            if ($schedule.monthly.isEnabled) {
                $rule = if ($schedule.monthly.isLastDayOfMonth) {
                    [pscustomobject]@{
                        kind = 'last-day'
                    }
                }
                else {
                    [pscustomobject]@{
                        kind      = 'nth-weekday'
                        occurence = [int] $ordinal[$schedule.monthly.dayNumberInMonth]
                        dayOfWeek = ConvrtTo-IsoWeekday $schedule.monthly.dayOfWeek
                    }
                }

                return [pscustomobject]@{
                    kind      = 'monthly'
                    localTime = [string] $schedule.monthly.localTime
                    months    = @($schedule.monthly.months)
                    rule      = $rule
                }
            }

            if ($schedule.periodically.isEnabled) {
                return [pscustomobject]@{
                    kind     = 'periodic'
                    interval = [int] $schedule.periodically.frequency
                    unit     = [string] $schedule.periodically.periodicallyKind
                }
            }

            if ($schedule.continuously.isEnabled) {
                return [pscustomobject]@{
                    kind = 'continuous'
                }
            }

            if ($schedule.afterThisJob.isEnabled) {
                return [pscustomobject]@{
                    kind = 'chained'
                    afterJobName = [string] $schedule.afterTHisJob.jobName

                }
            }

            return [pscustomobject]@{
                kind = 'unknown'
            }
        }

        function Format-VmScope($job) {
            $objs = @($job.virtualMachines.includes)
            $excludes = @($job.virtualMachines.excludes.disks) |
            Group-Object { $_.vmObject.objectId } -AsHashTable -AsString
            [pscustomobject]@{
                kind       = 'virtual_machines'
                count      = $objs.Count
                containers = @($objs | Where-Object { $_.type -ne 'VirtualMachine' }).Count
                items      = @(
                    foreach ($o in $objs) {
                        [pscustomobject]@{
                            name      = $o.name
                            type      = $o.type
                            host      = $o.hostName
                            size      = $o.size
                            exclusion = if ($excludes) { $excludes[$o.objectId].disksToProcess } else { $null }
                        }
                    }
                )
            }
        }

        function Format-ComputerScope($job) {
            $computers = @($job.computers)
            [pscustomobject]@{
                kind        = 'computers'
                count       = $computers.Count
                agent_type  = $job.agentType
                backup_mode = $job.backupMode
                items       = @(
                    foreach ($c in $computers) {
                        [pscustomobject]@{
                            name             = $c.name
                            type             = $c.type
                            path             = $c.path
                            protection_group = $c.protectionGroupId
                        }
                    }
                )
                files       = if ($job.files) {
                    [pscustomobject]@{
                        backup_os      = $job.files.backupOS
                        personal_files = $job.files.personalFiles.backupPersonalFiles
                        custom         = @($job.files.customFiles)
                        include_masks  = @($job.files.advancedSettings.includeMasks)
                        exclude_masks  = @($job.files.advancedSettings.excludeMasks)
                    }
                }
                else { 'none' }
            }
        }

        function Format-FileScope($job) {
            $objs = @($job.objects)
            [pscustomobject]@{
                kind  = 'file_shares'
                count = $objs.Count
                items = @(
                    foreach ($o in $objs) {
                        [pscustomobject]@{
                            path      = $o.path
                            server_id = $o.fileServerId
                            includes  = @($o.inclusionMask)
                            excludes  = @($o.exclusionMask)
                        }
                    }
                )
            }
        }

        function Format-CopyScope($job) {
            $inc = $job.sourceObjects.includes
            $srcJobs = @($inc.jobs)
            $srcRepos = @($inc.repositories)
            $srcBkps = @($inc.backups)
            [pscustomobject]@{
                kind     = 'sources'
                count    = $srcJobs.Count + $srcRepos.Count + $srcBkps.Count
                mode     = $job.mode
                items    = @(
                    foreach ($j in $srcJobs) { [pscustomobject]@{ source = 'job'; name = $j.name; type = $j.type; id = $j.id } }
                    foreach ($r in $srcRepos) { [pscustomobject]@{ source = 'repository'; name = $r.name; type = $r.type; id = $r.id } }
                    foreach ($b in $srcBkps) { [pscustomobject]@{ source = 'backup'; name = $b.name; type = $b.type; id = $b.id } }
                )
                excluded = @(
                    foreach ($e in @($job.sourceObjects.excludes.jobs)) { $e.name }
                    foreach ($e in @($job.sourceObjects.excludes.objects)) { $e.name }
                )
            }
        }

        function Format-WindowsWorkstationScope($job) {
            $protGroupId = $job.computers.protectionGroupId

            Write-Log "Encontrada protection group $($job.computers.path)" -Level INFO -Context "VMs"

            $jobsUri = "$baseUrl/api/v1/inventory/physical/$protGroupId"

            Write-Log "Consultando Workstations em: $jobsUri" -Level INFO -Context "VMs"


            $response = Invoke-RestMethod `
                -Uri            $jobsUri `
                -Method         POST `
                -Headers        $headers `
                -SkipCertificateCheck

            $objs = $response.data

            [pscustomobject]@{
                kind  = 'windows_workstation'
                count = $objs.Count - 1 # I think this gets the right number, since the endpoint exports itself so you remove only that (needs further testing)
                items = @(
                    $objs | ForEach-Object {
                        
                        if ($_.type -ne 'WindowsComputer') {
                            return
                        }
                        [pscustomobject]@{
                            name     = $_.name
                            type     = $_.type
                            platform = $_.platform
                        }
                    }
                )
            }
        }

        try {
            $storageRoot = switch ($job.type) {
                'FileBackup' { $job.backupRepository }
                'BackupCopy' { $job.target }
                default { $job.storage }
            }

            # A maioria dos tipos expoe o id direto no storage; o
            # WindowsAgentBackupWorkstationPolicy o aninha sob 'destination'.
            $repoId = $storageRoot.backupRepositoryId ?? $storageRoot.destination.backupRepositoryId

            $adv = $storageRoot.advancedSettings

            $scope = switch ($job.type) {
                'HyperVBackup' { Format-VmScope                 $job }
                'VSphereBackup' { Format-VmScope                 $job }
                'WindowsAgentBackup' { Format-ComputerScope           $job }
                'LinuxAgentBackup' { Format-ComputerScope           $job }
                'FileBackup' { Format-FileScope               $job }
                'BackupCopy' { Format-CopyScope               $job }
                'WindowsAgentBackupWorkstationPolicy' { Format-WindowsWorkstationScope $job }
                default {
                    [pscustomobject]@{ kind = 'unhandled'; count = 0; items = @(); raw = $job.type }
                }
            }
            
            [pscustomobject]@{
                id            = $job.id
                name          = $job.name
                type          = $job.type
                status        = if ($job.isDisabled) { 'disabled' } else { 'active' }
                high_priority = $job.isHighPriority
                scope         = $scope
                schedule      = Format-Schedule $job
                storage       = [pscustomobject]@{
                    repository = Get-RepositoryNameFromId -RepositoryId $repoId -RepositoryMap $repoMap
                    retention  = if ($storageRoot.retentionPolicy) {
                        [int]$storageRoot.retentionPolicy.quantity
                    }
                    else { $null }
                    gfs        = Format-GfsPolicy $storageRoot.gfsPolicy
                    full       = [pscustomobject]@{
                        active_full    = Format-FullPolicy $adv.activeFulls
                        synthetic_full = Format-FullPolicy $adv.synthenticFulls
                    }
                }
            }
        }
        catch {
            [pscustomobject]@{
                id    = $job.id
                name  = $job.name
                type  = $job.type
                error = $_.Exception.Message
            }
        }
    }

    $entry = $null
    while ($logQueue.TryDequeue([ref]$entry)) {
        Write-Log $entry.Message -Level $entry.Level -Context $entry.Context
    }

    $results | ConvertTo-Json -Depth 12

}
<div align="center">

# Veeam Inventory

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![version](https://img.shields.io/badge/version-0.1-blue)

</div>

A Powershell automation that collects backup and infrastructure information from the Veeam Backup & Replication REST API and converts the results into a normalized payload suitable for external processing.

# Overview

This powershell automation aims to audit and pre-process the backup environment for Veeam Backup & Replication for external uses, such as monthly reports.

## Currently Tested Job Types

| Job type            | Implemented | Tested  | Notes                             |
|---------------------|-------------|---------|-----------------------------------|
| Hyper-V VM Backup   | Yes         | Yes     | VM scope                          |
| Windows Agent Backup| Yes         | Yes     | Computer scope                    |
| File Share Backup   | Yes         | Yes     | File share scope                  |
| Backup Copy         | Yes         | Partial | Source normalization              |
| Windows Workstation | Yes         | Partial | Resolved through protection group |
| Windows Agent Policy| Yes         | Partial | Only windows                      |

# Quick Start

## 1. Clone the Repository

```bash
git clone https://github.com/angeluciel/veeam-inventory.git
cd veeam-inventory
``` 

## 2. Install the required PowerShell modules
Veeam-Inventory requires PowerShell 7 or newer, and uses `Microsoft.PowerShell.SecreStore` to store credentials.

```PowerShell
Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser
```

## 3. Create your configuration file
Copy the example configuration:
```PowerShell
Copy-Item .\config.example.psd1 .\config.psd1
```

Then edit `config.psd1` with the values for your environment.
`config.psd1` is ignored by Git and should contain Environment-specific configuration only.

## 4. Configure the credential store
Register a local SecretStore vault:
```PowerShell
Register-SecretVault `
  -Name LocalStore `
  -ModuleName Microsoft.PowerShell.SecretStore `
  -DefaultVault
```

Store the Veeam API credentials (required Administrator privileges on VBR):
```PowerShell
Set-Secret -Name VeeamApiUser -Secret 'service-account'
Set-Secret -name VeeamApiPassword -Secret (Read-Host -AsSecureString)
```

## 5. Configure non-interactive SecretStore access
Export the SecretStore password to the path configured in `PathToCredential`:

```PowerShell
Read-Host -AsSecureString |
  Export-Clixml -Path 'C:\VeeamInventory\credentials.clixml'
```
> Treat this file as sensitive. It allows the automation to unlock the credential store non-interactively.

## 6. Run the collector
From the repository root:

```PowerShell
pwsh -File .\VeeamInventory\main.ps1
```

To use a different configuration file:
```PowerShell
pwsh -File .\VeeamInventory\main.ps1 `
  -ConfigPath .\my-config.psd1
```

Once the collector works interactively, it can be scheduled with Windows Task Scheduler.

# Why this exists

I don't wanna pay for SQL Server, and big environments use too much of the database for Veeam ONE's SQL Server Express to be feasible.

With that in mind, I decided to create a way for me to generate reports like the ones I got in VONE in-house.

# Data it collects

The project currently collects:

- Backup Job ID, name and type
- Backup Job status (disabled / active)
- Backup Job priority (if it is high priority or not)
- Backup Job repository information, including:
  - Repository Name
  - Retention in days
  - GFS settings
  - Full Backup Settings (active and synthetic)
- Backup Job scope [see Scope](#scope)
- Backup Job Schedule [see Schedule](#schedule)
## Scope

The scope is a custom schema that formats the data depending on the **Job Type**.

All job types share the following fields:
- *kind*: Identifies the type of scope being represented.
- *count*: Total number of included objects or sources.
- *items*: Collections containing the objects included in the job scope.

The contents of `items`, as well as other additional properties, vary depending on the Job Type.

### VM Jobs
`kind: virtual_machines`

- Containers: Number of included objects that are containers rather than individual VMs.

Each object in `items` contains:
- Name: Object Name
- Type: Object Type
- Host: Host Associated with the object
- Size: Reported object size
- Exclusion: Disk excluded from processing for the objects, when configured.

### Computer / Agent Jobs
`kind: computers`

- agent_type: Agent type configured for the job
- backup_mode: Backup mode configured for the job
- files: File-level backup configuration. Returns `none` when no file is configured.

Each object in `items`contains:
- Name: Computer or protected object name
- Type: Object Type
- Path: Object Path
- protection_group: ID of the associated protection group

When `files` is present, it contains:
- backup_os: if the OS system files are included
- personal_files: whether personal files are included
- custom: custom files or paths configured for backup
- include_masks
- exclude_masks

### File Share Jobs
`kind: file_shares`

Each object in `items`contains:

- path: File share or object path.
- server_id: ID of the associated file server
- includes
- excludes

### Backup Copy Jobs
`kind: sources`

- mode: source-selection mode configured for the copy job.
- excluded: names of jobs or objects explicitly excluded from the source scope.

The `count` field represents the combined number of included jobs, repositories, and backups.

Each object in `items` contains:
- source: Possible values are `job`, `repository`, or `backup`.
- name: Source object name
- type: Source object type
- id: Source object ID

### Windows Workstation
`kind: windows_workstation`

The workstation scope is resolved through the protection group associated with the job.
The protection group inventory is queried and only objects of type `WindowsComputer` are included in the final scope.

Each object in `items` contains:
- name: Workstation name.
- type: Inventory object type.
- platform: platform reported for the workstation.

the count field represents the number of workstations returned by the protection group.
> Note: The current implementation calculated `count` as the total number of objects returned by the endpoint minus one, because the endpoint also appears to return the protection group itself. This behavior still required further validation.

## Schedule

The returned structure depends on the configured schedule type. The `kind` field identifies which format applied.

### Manual
`kind: manual`

Returned when automatic execution is disabled.

### Daily
`kind: daily`

collected fields:

- mode: Daily scheduling mode
- localTime: configured local execution time
- dayOfWeek: Days on which the jobs run, normalized to iso weekday values.

### Monthly
`kind: monthly`

- localTime: configured local execution time
- months: months in which the schedule is active
- rule: rule determining which day of the month the job runs

The monthly rule can have one of two formats:

For jobs configured to run on the last day of the month:
`kind: last-day`

For jobs configured around a particular weekday:
`kind: nth-wekday`

collected rule fields:
- occurrence: Which occurrence of the weekday should be used within the month.
- dayOfWeek: Weekday normalized to its ISO weekday value

### Periodic
`kind: periodic`

Used when the job runs repeatedly at a fixed interval.

Collected fields:
- interval: numeric frequency between executions.
- unit: unit associated with that frequency

### Continuous
`kind: continuous`

Returned when the job is configured for continuous execution

### Chained
`kind: chained`

Used when the job is configured to start after another job

Collected fields:
- afterJobName: Name of the job that must compelte before this job is started.

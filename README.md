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
Veeam-Inventory required PowerShell 7 or newer, and uses `Microsoft.PowerShell.SecreStore` to store credentials.

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

## Propósito

O script principal (`VeeamInventory/main.ps1`) roda como uma rotina agendada (ex.: Task Scheduler).

Para isso, ele:

1. Autentica na REST API do Veeam Backup & Replication via OAuth2.
2. Consulta o inventário de infraestrutura (hosts e VMs) e o catálogo de objetos protegidos.
3. Para cada objeto protegido, busca o restore point mais recente e monta um catálogo de "último backup por VM".
4. Cruza o inventário de VMs com esse catálogo para classificar cada VM em `OK`, `ATRASADO` ou `SEM_BACKUP`, com base em um limiar configurável de horas (`MaxHoursBackup`).
5. Levanta os jobs de backup e os repositórios configurados, normalizando-os em um formato mais legível (agenda, política de retenção, GFS, full ativo/sintético, escopo por tipo de job).
6. Consolida tudo em um payload único e envia via webhook para um sistema externo (hoje, um workflow n8n), que fica responsável por notificações, dashboards ou qualquer outra ação downstream.

O propósito é ser uma alternativa para os relatórios do VeeamONE, caso você não tenha.

## Fluxo de execução

```
Initialize-Logging -> Initialize-VeeamApi -> Unlock-VeeamCredentialStore -> Connect-VeeamApi
        │
        ├─ Get-ProtectedObjects -> Get-BackupCatalog -> Get-BackupStatus
        ├─ Get-InventoryVMs (Get-Hosts + Get-VMs)
        └─ Get-VeeamJobs + Get-VeeamRepositories -> ConvertTo-JobObject
        │
        └─ Send-N8nWebhook (payload consolidado)
```

## Módulos

### `modules/VeeamApi`

Encapsula toda a comunicação com a REST API do Veeam, para que o restante do código nunca lide diretamente com autenticação ou HTTP.

- **`Initialize-VeeamApi:`** guarda a configuração da sessão (URL base, versão da API, política de retry) em estado de módulo.
- **`Unlock-VeeamCredentialStore:`** - destrava o `Microsoft.PowerShell.SecretStore` local usando uma senha protegida em disco via `Export-Clixml` (criptografada com DPAPI, atrelada ao usuário/máquina que a gerou).
- **`Connect-VeeamApi:`** troca usuário/senha (lidos do SecretStore) por um token Bearer via `grant_type=Password`.
- **`Invoke-VeeamApi:`** wrapper de chamadas HTTP com retry/backoff configurável, tratando erros 4xx como definitivos e demais falhas como passíveis de nova tentativa.
- **`Get-VeeamApiStatistics:`** expõe contadores de chamadas, erros e retries da sessão atual, útil para diagnóstico.

Por padrão, o módulo assume um cofre `SecretStore` local com três segredos cadastrados: `VeeamApiUser`, `VeeamApiPassword` e `N8nApiKey`.

### `modules/PSLogging`

Logger simples e independente de qualquer integração externa.

- **`Initialize-Logging:`** define diretório e nível de log, gera um arquivo diário (`<prefixo>_yyyy-MM-dd.log`) e expurga logs mais antigos que `RetentionDays`.
- **`Write-Log:`** grava uma linha de log (console colorido + arquivo) com nível (`DEBUG`/`INFO`/`SUCCESS`/`WARN`/`ERROR`) e contexto (ex.: `AUTH`, `INVENT`, `N8N`), respeitando o nível mínimo configurado.
- **`Write-LogException:`** loga uma exceção de forma estruturada (mensagem, tipo, origem e stack trace), evitando repetir esse boilerplate em cada `catch`.

## Como substituir componentes

O desenho é modular pra que seja fácil trocar sem tocar no restante do fluxo, desde que o contrato seja mantido.

- **Destino do relatório:** hoje é um webhook n8n (`Send-N8nWebhook.ps1`), autenticado por API key em header. Para trocar por outro destino (Slack, Teams, banco de dados, SIEM), basta reescrever essa função para receber o mesmo `$Payload` e devolver `$true`/`$false` indicando sucesso; nada no `main.ps1` precisa mudar.
- **Cofre de credenciais:** a dependência em `SecretManagement`/`SecretStore` fica isolada em `Unlock-VeeamCredentialStore` e nas chamadas `Get-Secret` dentro de `Connect-VeeamApi`. Para usar outro backend (Azure Key Vault, variáveis de ambiente, um cofre corporativo), só essas duas funções precisam ser adaptadas.
- **Tipos de job suportados:** `ConvertTo-JobObject.ps1` tem um formatador dedicado por tipo de job (`Format-VmScope`, `Format-ComputerScope`, `Format-FileScope`, `Format-CopyScope`). Tipos não mapeados caem em um bucket `unhandled` sem quebrar o restante do processamento; novos tipos de job do Veeam são suportados adicionando um novo formatador e um novo `case` no `switch`.
- **Critério de "backup em dia":** hoje é puramente temporal (`MaxHoursBackup`, comparado contra o `restorePoint` mais recente). Para um critério mais sofisticado (ex.: considerar apenas full backups, ou pontos íntegros/verificados), o ponto de extensão é `Get-BackupStatus.ps1`.
- **Paralelismo:** as consultas de VM por host (`Get-VMs.ps1`) e a normalização de jobs (`ConvertTo-JobObject.ps1`) usam `ForEach-Object -Parallel`, com throttle configurável por parâmetro; ajustar esse número é o principal botão de performance vs. carga na API do Veeam.

## Instalação

**Pré-requisitos:**

- PowerShell 7 ou superior.
- Acesso de rede à REST API do Veeam Backup & Replication (porta padrão `9419`).
- Módulos `Microsoft.PowerShell.SecretManagement` e `Microsoft.PowerShell.SecretStore` instalados:

  ```powershell
  Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser
  ```

- Um cofre `SecretStore` registrado e populado com as credenciais usadas pela automação:

  ```powershell
  Register-SecretVault -Name LocalStore -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
  Set-Secret -Name VeeamApiUser     -Secret 'usuario-de-servico'
  Set-Secret -Name VeeamApiPassword -Secret (Read-Host -AsSecureString)
  Set-Secret -Name N8nApiKey        -Secret (Read-Host -AsSecureString)
  ```

- A senha do cofre exportada para o arquivo apontado por `PathToCredential`, para permitir o unlock não-interativo (`Unlock-VeeamCredentialStore`):

  ```powershell
  Read-Host -AsSecureString | Export-Clixml -Path 'C:\Scripts\Veeam\vault.clixml'
  ```

  > Esse arquivo contém a chave do cofre de credenciais, trate-o com o mesmo cuidado de uma senha em texto puro. Ele já está no `.gitignore` do repositório.

## Configuração

Os parâmetros de execução ficam centralizados no bloco `$config` no topo de `VeeamInventory/main.ps1`:

| Campo | Descrição |
|---|---|
| `N8NUri` | URL do webhook de destino do relatório. |
| `VeeamBaseUrl` | URL base da REST API do Veeam (ex.: `https://veeam.exemplo.local:9419`). |
| `PathToCredential` | Caminho do `.clixml` com a senha do `SecretStore`. |
| `ApiVersion` | Versão da REST API do Veeam a utilizar no header `x-api-version`. |
| `SchemaVersion` | Versão do schema do payload enviado ao webhook, para o consumidor validar compatibilidade. |
| `MaxHoursBackup` | Limiar, em horas, a partir do qual uma VM com backup é considerada `ATRASADO`. |
| `LogDirectory` | Pasta onde os logs diários são gravados. |
| `LogLevel` | Nível mínimo de log exibido/gravado (`DEBUG` a `ERROR`). |
| `LogRetentionDays` | Dias de retenção dos arquivos de log antes de serem expurgados. |

## Uso

Execute o script principal com PowerShell 7+:

```powershell
pwsh -File "VeeamInventory/main.ps1"
```

Ao final de uma execução bem-sucedida, a função `Main` retorna o objeto de payload completo (o mesmo enviado ao webhook), o que facilita testar o script interativamente no console antes de agendá-lo. Em caso de falha em qualquer etapa, o erro é logado com contexto e o script encerra com código de saída `1`, adequado para monitoramento via agendador de tarefas.

Para rodar de forma recorrente, agende `main.ps1` via Task Scheduler (Windows) ou `cron`/`systemd timer` (Linux), com a frequência alinhada ao `MaxHoursBackup` configurado.

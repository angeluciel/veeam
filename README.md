# Veeam Inventory

Automação em PowerShell que audita a cobertura de backup do ambiente Veeam Backup & Replication e publica um relatório consolidado em um sistema externo de orquestração/alertas.

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

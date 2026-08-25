# Contributing

Contributions are welcome.

Veeam Inventory is still an early project, so bug reports, testing against
different Veeam environments, documentation improvements, and support for
additional job types are particularly useful.

Especially wanted right now:

- Testing against VMware / vSphere environments (only Hyper-V has been exercised so far)
- Confirming or correcting the job types marked **Partial** in the README support table
- Sanitized real-world API responses for job types that currently fall into the
  `unhandled` bucket
- Making the project usable without an n8n endpoint

## Reporting Issues

Before opening an issue, please check whether a similar issue already exists.

When reporting a bug, include:

- Veeam Backup & Replication version
- REST API version (the value of `ApiVersion` in your config)
- PowerShell version (`$PSVersionTable.PSVersion`)
- Job type involved
- The commit you are running (`git rev-parse --short HEAD`)
- Expected behavior
- Actual behavior
- Relevant sanitized logs or API responses

Do not include credentials, API tokens, infrastructure secrets, customer
information, or other sensitive data. When attaching an API response or a log
line, replace host names, VM names, client names, IP addresses and object IDs
with placeholders. The shape of the JSON is what matters, not the values.

## Development Setup

Requirements:

- PowerShell 7 or newer
- Network access to a Veeam Backup & Replication REST API (default port `9419`)
- A service account with permission to read jobs, repositories and inventory

Clone the repository:

```powershell
git clone https://github.com/angeluciel/veeam-inventory.git
cd veeam-inventory
```

Install the required modules:

```powershell
Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser
```

Create your configuration from the example and fill in your environment:

```powershell
Copy-Item .\config.example.psd1 .\config.psd1
```

`config.psd1`, `*.clixml` and log files are ignored by Git. Never commit them,
and never add a real host name, client name or webhook URL to
`config.example.psd1`.

Register a local vault and store the secrets the automation expects
(`VeeamApiUser`, `VeeamApiPassword`, `N8nApiKey`):

```powershell
Register-SecretVault -Name LocalStore -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
Set-Secret -Name VeeamApiUser     -Secret 'service-account'
Set-Secret -Name VeeamApiPassword -Secret (Read-Host -AsSecureString)
Set-Secret -Name N8nApiKey        -Secret (Read-Host -AsSecureString)
```

Export the vault password so the collector can unlock it non-interactively:

```powershell
Read-Host -AsSecureString | Export-Clixml -Path 'C:\VeeamInventory\credentials.clixml'
```

Run the collector against your own config:

```powershell
pwsh -File .\VeeamInventory\main.ps1 -ConfigPath .\config.psd1
```

`Main` returns the full payload on success, so you can inspect the result
interactively before touching the webhook side.

### Testing without an n8n endpoint

There is currently no dry-run switch, and `main.ps1` treats a failed webhook
delivery as a fatal error. While developing, point `N8NUri` at a throwaway
request-capture endpoint of your own rather than at a production workflow.
A PR adding a proper `-NoSend` / `-DryRun` switch would be very welcome.

There is no automated test suite yet. "Tested" in this project means: run
end to end against a real VBR server, and confirm the emitted payload matches
what the Veeam console shows. Say which environment you tested against in your
PR, including the VBR version and job types involved.

## Project Layout

```
VeeamInventory/
  main.ps1                  entry point and orchestration
  Public/                   functions called directly from main.ps1
  Private/Veeam/            REST API queries (jobs, repositories, restore points)
  Private/Infra/            inventory queries (hosts, VMs)
  Private/Adapter/          normalization into the outgoing payload
modules/VeeamApi/           auth, retry/backoff, session state
modules/PSLogging/          logging
```

Rules of thumb:

- Anything that talks HTTP to Veeam belongs in `modules/VeeamApi` or
  `Private/Veeam`; the rest of the code should not build requests by hand.
- Anything that reshapes Veeam data into the outgoing payload belongs in
  `Private/Adapter`.
- New files under `VeeamInventory/` must be dot-sourced in the import region at
  the top of `main.ps1`.

## Code Style

- Four-space indentation, no tabs.
- Approved PowerShell verbs, `Verb-Noun` naming, one function per file, file
  named after the function.
- PascalCase for parameters (`-Headers`, `-BaseUrl`), camelCase for local
  variables. Call parameters with their declared casing.
- Use `[CmdletBinding()]` and mark required parameters `[Parameter(Mandatory)]`.
- Add comment-based help (at minimum `.SYNOPSIS`) to new functions.
- `throw` on failure inside functions; only `main.ps1` decides to `exit`.
  Existing `exit 1` calls inside helper functions are a bug, not a pattern to
  copy.
- Log through `Write-Log` with an appropriate `-Level` and a short `-Context`
  tag, and use `Write-LogException` in `catch` blocks rather than reformatting
  exceptions by hand.
- `-SkipCertificateCheck` is used throughout because most VBR deployments use a
  self-signed certificate. Do not add new certificate-handling behavior without
  discussing it in an issue first.
- Keys in the emitted payload are `snake_case` or `camelCase` as already used —
  match the surrounding structure rather than introducing a third convention.

### Language

Code identifiers, comments, documentation and commit messages should be in
English. Parts of the codebase and README are currently in Portuguese; the
project is standardizing on English, so new contributions should be English and
translation PRs are welcome. One exception: the payload status values
(`OK`, `ATRASADO`, `SEM_BACKUP`) are consumed downstream, so do not rename them
without bumping `SchemaVersion` (see below).

## Adding Support for a New Job Type

This is the most common contribution. The steps:

1. Add a `Format-*Scope` function in `Private/Adapter/ConvertTo-JobObject.ps1`
   that returns an object with the shared `kind`, `count` and `items` fields,
   plus whatever is specific to that job type.
2. Add a `case` for the Veeam job type string in the `switch`. Unmapped types
   fall into the `unhandled` bucket, so nothing else breaks if you miss one.
3. Document the new `kind` and its fields in the **Scope** section of the
   README, following the existing format.
4. Add a row to the job type table at the top of the README, and be honest in
   the Tested column — `Partial` is a useful and acceptable answer.
5. Include a sanitized sample of the raw Veeam response for that job type in the
   PR description. It makes review possible without access to your environment.

## Changing the Payload

The payload carries a `SchemaVersion` so downstream consumers can validate
compatibility. If your change adds, removes, renames or retypes a field in the
object sent to the webhook, bump `SchemaVersion` in `config.example.psd1` and
say so explicitly in the PR description. Purely additive changes to a `scope`
block for a job type that previously fell under `unhandled` do not need a bump.

## Adding a Configuration Value

When you add a key that `main.ps1` reads from the config file:

1. Add it to `config.example.psd1` with a safe placeholder value.
2. Document it in the configuration table in the README.
3. Give it a sensible default, or add it to the `requiredSettings` validation
   list in `main.ps1` so the script fails early with a clear message.

## Commits and Pull Requests

- Work on a branch off `main` and open a pull request against `main`.
- Keep commits focused; one logical change per commit. Short imperative subject
  lines (`Add file share scope formatter`) are preferred.
- One concern per PR. A new job type and a refactor of the logging module should
  be two PRs.
- In the PR description, cover: what changed, why, which VBR version and job
  types you tested against, and whether the payload shape changed.
- Documentation-only and typo fixes are welcome and do not need any of the
  above ceremony.

If you are planning something large — replacing the webhook destination with a
pluggable output, swapping the credential backend, adding a test harness — open
an issue first so the interface can be agreed before you write the code.

## Security

Do not open a public issue for a security problem. Report it privately to the
maintainer instead.

Because this project handles backup infrastructure credentials, please be
careful that PRs never introduce logging of tokens, passwords or the contents
of the credential store, and never widen what gets written to the log
directory.

## License

By contributing, you agree that your contributions are licensed under the
MIT License that covers this project.

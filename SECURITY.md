# Security Policy

Veeam Inventory reads from backup infrastructure using a privileged service
account, unlocks a local credential store non-interactively, and emits a
document describing the protection state of an entire environment. Security
issues in this project are worth reporting even when they look minor.

## Reporting a Vulnerability

**Do not open a public issue for a security problem.**

Report privately through GitHub's private vulnerability reporting on this
repository (**Security** tab -> **Report a vulnerability**), or by email to
`jpmizidoro@gmail.com`.

Please include:

- A description of the issue and why it is a security problem
- Steps to reproduce, or the code path involved
- The commit you are looking at
- Affected VBR version and PowerShell version, if relevant
- Any suggested fix

Sanitize anything you attach. Replace host names, VM names, client names,
object IDs, tokens and URLs with placeholders.
The shape of the data is what matters for triage.

This is a single-maintainer project with no funded response process. Expect an
acknowledgement within about a week. If a fix is needed, it will land on `main`
and the advisory will be published once the fix is available. There is no bug
bounty. Credit will be given unless you ask otherwise.

## What to Report Elsewhere

- **Vulnerabilities in Veeam Backup & Replication itself, or in its REST API**:
  report to Veeam, not here. Veeam operates a vulnerability disclosure program;
  see the Veeam Trust Center for the current reporting form.
- **Vulnerabilities in n8n, PowerShell, or the `Microsoft.PowerShell.SecretManagement`
  and `SecretStore` modules**: report to those projects.
- Issues in how *this* project uses any of the above are in scope here.

## Supported Versions

This project is pre-1.0. Only the current `main` is supported; fixes are not
backported to earlier commits or tags. If you are running this in production,
pin to a commit you have reviewed and update deliberately.

## Security Model

The project assumes:

- The machine running the collector is trusted, hardened, and treated with the
  same care as the backup server itself. It effectively holds keys to the
  backup infrastructure.
- The service account used is dedicated to this automation, not shared with
  interactive administration.
- The credential file (`PathToCredential`) is DPAPI-encrypted and therefore
  bound to the user account and machine that created it. It is not portable,
  but it is also not protected against anything running as that user on that
  machine.
- The webhook destination and the transport to it are trusted.

If any of those assumptions do not hold in your environment, this tool
increases your risk rather than reducing it.

## Known Risk Areas

These are understood properties of the current design, not undisclosed bugs.
Reports that simply restate them are welcome as issues but are not treated as
vulnerabilities.
If you know of ways to improve any of those, I'd be glad to listen!

- **TLS verification is disabled.** `-SkipCertificateCheck` is used on every
  call to the Veeam API, because most VBR deployments present a self-signed
  certificate. The consequence is that the OAuth password grant and the bearer
  token are exposed to an active man-in-the-middle on that path. Run the
  collector on a network segment where that is an acceptable trade-off, or with
  the VBR certificate replaced by one your machine trusts.
- **Password grant authentication.** Credentials are exchanged for a bearer
  token via `grant_type=Password`. The account password exists in memory during
  that exchange.
- **Vault key on disk.** The exported `.clixml` allows non-interactive unlock of
  the credential store. Anyone able to run code as that user on that host can
  unlock the vault. Restrict file ACLs to the service account and audit access
  to it.
- **The payload is sensitive.** The document sent to the webhook contains host
  and VM names, repository names, retention and GFS policy, schedules, and
  **most importantly** an explicit list of unprotected and overdue machines. That
  is a target list. Treat the webhook endpoint, its transport, and whatever
  stores the result downstream as systems handling confidential infrastructure
  data.
- **Bearer tokens cross runspace boundaries.** `Get-VMs` and `ConvertTo-JobObject`
  pass the headers hashtable into parallel runspaces. Any change that logs or
  serializes those headers would leak a live token into the log directory.
- **Logs persist.** Log files contain VM names and job names and are retained
  for `LogRetentionDays`. They belong on protected storage.

## Hardening Recommendations

- Restrict NTFS permissions on the credential file, the config file and the log
  directory to the service account only.
- Send the webhook over HTTPS to an endpoint you control, authenticated, and
  ideally reachable only from the collector host.
- Keep `config.psd1`, `*.clixml` and logs out of version control. The
  `.gitignore` covers these, but verify before your first push.
- Rotate the service account password and the n8n API key on a schedule, and
  regenerate the credential file when you do.
- Review diffs before updating, as you would for anything with this level of
  access.

## Out of Scope

- The requirement for a privileged VBR account. It is inherent to what the tool
  reads.
- The credential file being readable by the account it was created for. That is
  how DPAPI-bound non-interactive unlock works.
- Findings that require an attacker to already have administrative access to
  the collector host or the backup server.
- Vulnerabilities that only apply when the maintainer's documented
  recommendations above are ignored.

## Contributions

Pull requests that reduce this attack surface are welcome. Pluggable
credential backends, optional certificate validation, redaction or translation
in logging, a `-DryRun` mode that avoids sending real inventory to a test endpoint.
Open an issue first for anything that changes the credential or transport model.

Contributions must never introduce logging of tokens, passwords or credential
store contents, and must not widen what is written to the log directory.

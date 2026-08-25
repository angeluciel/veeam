# Summary

<!-- What changed and why. One or two paragraphs is plenty. -->

Fixes #

## Type of change

<!-- Delete what does not apply. -->

- Bug fix
- New job type support
- New feature
- Refactor
- Documentation
- Tooling

## Testing

<!--
There is no automated test suite. "Tested" here means run end to end against a
real VBR server, with the output compared against what the Veeam console shows.
If you could not test something, say so plainly. That is useful information,
not a problem.
-->

- Veeam Backup and Replication version:
- REST API version:
- PowerShell version:
- Job types exercised:
- Hypervisor platform:

What I verified:

<!-- For example: the file share job now emits a file_shares scope with the
     correct include and exclude lists, matching the job settings in the console. -->

What I could not verify:

## Payload impact

<!-- Delete what does not apply. -->

- No change to the payload
- Additive only (new fields, or a job type that previously fell under `unhandled`)
- Breaking for downstream consumers, and `SchemaVersion` has been bumped

## Checklist

- [ ] New functions follow the naming and style conventions in CONTRIBUTING
- [ ] New files under `VeeamInventory/` are dot-sourced in `main.ps1`
- [ ] Functions `throw` on failure rather than calling `exit`
- [ ] New configuration keys are in `config.example.psd1`, documented in the README, and given a default or added to the required settings check
- [ ] New job types are documented in the README Scope section and added to the support table with an honest Tested value
- [ ] README and CONTRIBUTING updated where behavior changed
- [ ] No credentials, tokens, host names, VM names, client names or webhook URLs in the diff, in test fixtures, or in the PR description
- [ ] Nothing new is written to the log directory that could contain secrets or tokens
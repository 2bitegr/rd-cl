# Security Policy

## Reporting Vulnerabilities

Report security issues for the Exantas Support distribution privately to
security@2bite.gr.

For upstream RustDesk vulnerabilities, also follow RustDesk's upstream security
process where applicable.

## Secret Handling

This public repository must not contain production secrets or credentials.

Never commit:

- permanent unattended passwords
- password hashes or salts that grant access to deployed devices
- Office API admin credentials
- API tokens
- database credentials
- webhook secrets
- private RustDesk server keys
- code-signing certificates or private keys
- update signing keys
- per-device unattended credentials
- customer enrollment tokens

Public RustDesk server endpoints and the RustDesk server public verification key
may be present because they are not credentials. The corresponding private server
key must stay outside this repository.

## Release Safety

Before publishing a release or pushing to the public source repository:

1. Run the public release checks in `scripts/check-public-release.sh`.
2. Review `git status --short --untracked-files=all`.
3. Confirm no generated Windows metadata files are staged.
4. Confirm each binary release maps to a public git tag.
5. Confirm the app About view, download page, and release notes link to the
   source repository.

## Unattended Access Rule

The generic installer must not contain a shared unattended credential.

Without Office enrollment, Exantas Support runs in attended basic support mode.
The basic mode one-time password is numeric-only so a final customer can read it
over the phone. Managed unattended access is enabled only after Office
enrollment creates or rotates per-device credentials under Office policy.

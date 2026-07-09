# AGPL Compliance Notes

Exantas Support is a modified RustDesk client distribution. RustDesk is licensed
under AGPLv3, so binary releases must provide Corresponding Source.

Official license text:

```text
https://www.gnu.org/licenses/agpl-3.0.html
```

## Release Requirements

For each distributed MSI or portable executable:

- publish the corresponding source in `https://github.com/2bitegr/rd-cl`
- tag the source used for the binary release
- include build and install scripts needed to generate, install, run, and modify
  the program
- include license notices and attribution
- provide a visible Source Code link from the app, download page, and release
  notes
- avoid adding restrictions that conflict with AGPLv3

## Not Required In Public Source

AGPL does not require publishing production secrets.

Do not publish:

- private server keys
- shared unattended passwords
- per-device unattended credentials
- Office API credentials
- database credentials
- signing certificates or private keys
- update signing keys
- webhook secrets
- customer enrollment tokens

## Public Defaults

Self-hosted routing values can remain public when they are not credentials.
The RustDesk server public verification key is treated as public key material.
The matching private key stays only on the server.

## Product Modes

Basic support mode works without enrollment and allows only attended access by
ID plus numeric one-time password or click approval.

Managed support mode requires Office enrollment before unattended access,
policy sync, device management, and native companion automation are enabled.

Office login is separate from customer device enrollment. Office users inherit
their support role from Office, such as `admin` or `technician`. Final-customer
device enrollment still requires an install link or install code.

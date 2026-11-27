# Windows installer update readiness

Local source candidate, 2026-11-26; publication preparation 2026-11-27 assigns
version 3.2.12. Source publication is pending. Delivered 3.2.11 remains the
baseline; this is not a new installer or native acceptance receipt.

The interactive install page shows pre-install diagnostics. Successful install
starts the installed main app with `--office-install-check`, preserving the
existing customer enrollment handoff, and then shows completion/readiness in
the same rd-cl UI. The postcheck retries read-only evidence for at most two
minutes to accommodate service startup/enrollment, then offers manual recheck.
Silent install does not introduce UI or remediation prompts.

Native `--office-install-readiness [target-directory]` returns schema-1 JSON.
Before installation or when the installed service cannot be contacted, evidence
is partial. After installation, the existing authorized service IPC supplies
SYSTEM checks, the protected runtime probe and an authenticated read-only Office
readiness response. It never uses the mutating worker poll as a diagnostic.
Logs may be initialized by ordinary native startup; the inspection itself does
not change registry/service/enrollment/update-job state.

Readiness requires every mandatory local check, versions, fresh timestamps and
confirmed Office evidence. It does not promise a future update: busy sessions,
disk needs, schedules, policy and the hosted release are rechecked by the worker.
Expired, incomplete, denied or unavailable evidence stays unknown.

The installer offers only named service actions (start and automatic startup),
one confirmation per action, followed by normal UAC, fresh snapshot/path/ACL
validation and readback. Native `--office-install-repair ACTION FINGERPRINT`
accepts only these closed actions, never an executable, supplied script or registry
path. Active update barriers, MSI/unknown ownership and changed snapshots refuse
repair. Windows Update opens its normal settings UI without claiming a repair or
reboot. Nothing clears pending-file operations, changes security settings, resets
identity or silently closes sessions. Public key mismatch requires reviewed trust
repair; existing machine keys are not replaced.

Worker reboot detection and effective installation path/ACL checks use the
embedded `res/office-readiness.ps1` library.
Standalone source tests load that adjacent file; packaged workers receive the
library after their parameter block from the native core. Existing report and
permit contracts stay intact. No codec inputs or dependency versions changed.

Tests: `scripts/tests/test_windows_install_readiness.py` runs PowerShell provider
fixtures and shared-library composition checks. Dart model/widget cases are in
`flutter/test/exantas_install_readiness_test.dart` and the S2 regression list.
Office's `docs/rdcl-installer-readiness.md` describes the additive read-only API,
CallerPopup health projection and separate native/production acceptance gates.
Use source revision + dirty caveat for these checks; never reuse this candidate
as the previously delivered 3.2.11 binary or claim native PASS from Linux parsing.

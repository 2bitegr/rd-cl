# Native Caller Popup connection fix —2026-10-28

## REVIEW — rd-cl2.0.3+75 source;S2 build pending

User confirms existing Office sign-in/native-ready status BEFORE failure. Manual
main-window connection to same peer works;Caller Popup returns please login.
Source gap:URI desktop dispatch bypasses ensureNativeReady. Now delegates to the
same connectMainDesktop gateway,retaining officeTicket/switchUuid/password/relay.
Protected tickets require current companion/native readiness;local playback and
legacy account behavior preserved. No server policy/issuer/permission change.
No new FFI/dependency/SDK/codec/icon or protocol pins. Profile/product versions
updated;new Windows EXE required,not an Office redeploy. Manual connection works
as temporary path;no logout/customer re-registration is needed.

Source guards83PASS/8platformSKIP and Dart syntax PASS;these are not Windows
behavioral acceptance. Evidence:Reports/native-login-ready-current. Pinned
Flutter analyzer/behavioral route/native DLL/Windows/DPAPI acceptance NOT_RUN here;
new2.0.3 EXE NOT_PRODUCED/hosting NOT_PUBLISHED. Native entrypoint acceptance gap
is documented in docs/office-native-auth.md. Exact published SHA is required before
an executable S2 build prompt;preserve current packages/caches and don't duplicate
completed builds. After review/publication use one build+hosting prompt with the
Office exact-volume guard and single previous-EXE retirement,never broad cleanup.

## DONE — completed/native hosted baseline2.0.2+74

Source680628f2b9e798ef63e6d29c73954807d9012e12;24343040bytes,UNSIGNED,SHA256
 d4843ebf32759b78f2663247d6fd72cb4ba7a2ce2229c9f59131186a4fa292a1.
S2 reports build/package/maintenance/HTTPS publication PASS,86Dart tests,90guards
plus1SKIP,125checksums;Windows installation/enrollment NOT_RUN. Keep hosted EXE
until new verified publication;S2 rollback/caches remain. Docs-only3f3fcd308 was
published after baseline;no extra native build was needed for those instructions.
Office current published67c7d775deb152405f2e83b797a24a14292ad774,1.12.20;
Popup1.4.13 package verified,111contract cases,Windows acceptance NOT_RUN.

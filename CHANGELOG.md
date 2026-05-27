# Changelog - ATS Proxy Enterprise

## Unreleased - v3.0 beta architecture

### Added
- Plugin source `src/ats_proxy_filter_v30.c` with modes `off`, `deny`, `whitelist`, `auth_all`, `auth_nd`.
- Split configuration examples in `config/`: `filter.conf`, `deny.list`, `whitelist.list`, `admin.list`, `auth.conf`.
- `scripts/ats-ctl` for mode/list/user management without manual root-owned edits.
- `scripts/compile-plugin.sh` for repeatable plugin builds against ATS 9/10 source trees.
- `scripts/ats-mode-test.sh` for mode-specific runtime validation.
- v3.0 documentation: architecture, plugin filtering/auth, ATS LTS install target, ATS manual, enterprise reliability note.

### Security
- v3.0 auth design stores `salt$sha256(salt+password)` instead of plaintext passwords.
- v3.0 auth comparison uses constant-time string comparison.
- v3.0 client IP extraction uses `inet_ntop` for IPv4 and IPv6.

### Not yet validated
- Runtime ATS 10.1.2 on Ubuntu 26.04.
- v3.0 plugin compile/load/regression on ATS 10.
- TLS frontend with v3.0.

## 0.14.0 - 2026-05-26

### Changed
- **Documentazione ricostruita** con stile archivio storico (guide da 80-107 righe → 503-1455 righe)
- `README.md`: manifesto ICT con 10 principi, mappatura normativa GDPR/NIS2/ISO 27001, quick start, risultati validati, badge
- `GUIDA_INSTALLAZIONE.md`: guida completa con percorso manuale (comandi copia-incolla) + automatizzato (install-ats-proxy.sh), dual-OS 🔵/🟢, troubleshooting 14 voci, checklist pre-prod 23 voci
- `GUIDA_OPERATIVA.md`: guida unificata day-to-day + CVE + GDPR + incident response + troubleshooting. Include: gestione ACL/utenti, monitoraggio, backup/restore, hardening audit, upgrade ATS, compatibilità 9.x→10.x, gestione CVE con cve-check.sh, severity matrix, rollback, regression test, debug, compliance GDPR (Art.15/17), incident response con template NIS2/GDPR, checklist mensile
- Guide root-level obsolete archiviate in `archive/storico/v0.13.0/`

### Verified
- Allineamento al MANIFESTO_ICT.md v1.0 (6 domande di verifica)
- Allineamento ai Principi Operativi ICT (documentazione profonda, codice responsabilità, automazione governabile)
- Stile ereditato da `archive/storico/GUIDA_*_v1.0.md` (blocchi OS color-coded, tabelle troubleshooting, checklist, comandi con output atteso, mappatura normativa integrata)
- DNS cache gap non riprodotto nei test v0.13.0 su VM135/VM136 (richieste auth-gated restano `407`, whitelist genera log ripetuti)
- Admin bypass da IP remoto `192.168.89.55` confermato su VM135

### Known Limitations
- ATS 10.x remains not validated (requires C++17, generated build headers, CMake build system)
- TLS frontend on port 8443 implemented in installer but not in end-to-end test battery
- Load beyond 50 concurrent requests not validated
- Formal vulnerability assessment procedure not yet defined
- Annual penetration test not yet performed
- FEL-1.0/CLA legal review pending

## 0.13.0 - 2026-05-26

### Added
- `scripts/ats-hardening-check.sh` to verify systemd hardening, UFW, fail2ban, unattended upgrades, etckeeper, config permissions, health check and CVE helper.
- `GUIDA_INSTALLAZIONE_TESTATA.md` as the current installation guide backed by VM tests.
- `GUIDA_AGGIORNAMENTO_TESTATA.md` as the current update guide, with ATS 10.x explicitly marked non-validated.

### Changed
- `scripts/install-ats-proxy.sh` now supports config-file values with interactive fallback for missing/placeholder values.
- ATS download verification now uses the official SHA512 hash instead of the unavailable `.sha256` URL.
- Installer is idempotent for cached ATS/PCRE tarballs and cleans stale source trees before extraction.
- fail2ban config is written to `/etc/fail2ban/jail.d/ats-proxy.local` and the service is restarted so the `ats-proxy` jail is active immediately.
- Root documentation consolidated: README is now manifesto + quick start, historical guides moved to `archive/storico/`.

### Verified
- Full installer on VM135 Ubuntu 24.04.4: OK.
- Full installer on VM136 Ubuntu 26.04: OK.
- Regression on both VMs: `Passed: 9 Failed: 0`.
- Hardening on both VMs: `Passed: 25 Failed: 0 Warnings: 0`.
- Admin bypass from remote client IP `192.168.89.55` on VM135: DENY host bypassed (`200`) and auth-gated host bypassed (`301`) with `ADMIN bypass` logs.
- DNS cache quick test on current plugin: repeated auth-gated no-auth requests remained `407` on VM135/VM136; repeated whitelist requests generated repeated plugin logs.
- Old recovered plugin SHA `6a1a73...` tested temporarily on VM135: no better DNS-cache behavior observed; current plugin SHA `26c437...` restored.
- ATS 10.1.2 raw-header compile check: not drop-in; requires C++17 and generated build headers.

### Known Limitations
- ATS 10.x remains not validated.
- TLS frontend option remains not included in the 2026-05-26 end-to-end test battery.
- Load beyond 50 concurrent requests remains not validated in this session.

## 0.12.0 - 2026-05-26

### Added
- API-corrected `src/ats_proxy_filter_v21.c` compiled and tested against ATS 9.2.13.
- Rebuilt `bin/ats_proxy_filter_v21.so` from source (SHA256: 26c4371d).
- Full test validation: VM135 (Ubuntu 24.04) and VM136 (Ubuntu 26.04) both pass complete battery.

### Changed
- Plugin binary now built from source, not recovered from legacy VMs.
- `ARTIFACTS.md` updated with compilation provenance and new SHA256.
- All guides confirmed against real VM test results.

### Fixed
- 403 reason phrase corrected to "Forbidden" (was "INKApi Error" in intermediate builds).
- Source compiles with correct ATS 9.2.13 API (TSUserArg*, TSMimeHdrFieldValueStringInsert, TSHttpTxnClientAddrGet).
- `records.config` fix: installer now overwrites default `remap_required=0` and `reverse_proxy.enabled=0`.

### Known Limitations
- OS_DNS_HOOK DNS cache gap: after first request to a domain, cached DNS bypasses plugin auth/deny on subsequent requests.
- Plugin binary directory is `/opt/trafficserver/libexec/trafficserver/` in ATS 9.2.13 (not `lib/modules`).

## 0.10.0 - 2026-05-25

### Added
- Versioned recovered plugin binary: `bin/ats_proxy_filter_v21.so`.
- Added `ARTIFACTS.md` with binary provenance, hash and source-code status.
- Added `TEST_MATRIX.md` to record tested commands and validation gaps.
- Added `scripts/check-repo-consistency.sh` to prevent missing referenced artifacts.
- Added `ROOT_CAUSE_REPLICABILITA_v1.0.md` to document why the artifact gap happened and how to prevent recurrence.
- Added private-repo transfer workflow: `GUIDA_TRASFERIMENTO_VM_v1.0.md`.
- Added reproducible deploy workflow: `GUIDA_REPLICABILITA_DEPLOY_v1.0.md`.
- Added packaging script: `scripts/package-release.sh`.
- Added OS-specific wrappers: `scripts/install-24.04.sh`, `scripts/install-26.04.sh`.
- Added preflight validation: `scripts/preflight.sh`.
- Added env templates: `env/ats-proxy.env.example`, `env/proxmox.env.example`.

### Changed
- Installer now supports `--env`, `--plugin`, `--validate-only` and non-interactive validation before system changes.
- Installer and templates default to `./bin/ats_proxy_filter_v21.so`.
- Packaging now includes the versioned plugin binary by default.
- Documentation now distinguishes between recovered binary and missing C source.

### Fixed
- Removed misleading current-doc claims that the plugin binary is not versioned.
- Removed realistic example passwords from current templates and active guide examples.

### Known Gaps
- `ats_proxy_filter_v21.c` original source is not recovered yet.
- Full end-to-end install still needs validation on clean/snapshot Ubuntu 24.04 and 26.04 VMs.
- 403 reason phrase still needs live validation with the recovered binary.

## Historical Notes

Earlier commits documented VM-tested behavior but did not include the plugin source or binary as tracked artifacts. This caused references to `ats_proxy_filter_v21.c`/`.so` without a repo-resolvable file. Version `0.10.0` fixes the binary artifact gap and adds consistency checks to prevent recurrence.

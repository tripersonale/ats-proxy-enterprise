# Changelog - ATS Proxy Enterprise

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

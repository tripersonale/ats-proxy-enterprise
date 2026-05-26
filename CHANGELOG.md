# Changelog - ATS Proxy Enterprise

## 0.11.0 - 2026-05-25

### Added
- Reconstructed `src/ats_proxy_filter_v21.c` from documented behavior and ATS `basic_auth.c` base.
- Added `src/README.md` documenting expected source location.
- Added `scripts/ats-regression-test.sh` for automated proxy test battery.
- Added `scripts/ats-version-report.sh` for environment audit without secrets.

### Changed
- `ARTIFACTS.md`: source status changed from Missing to Versioned with SHA256.
- All guides updated: source no longer marked as missing in current documentation.
- `scripts/check-repo-consistency.sh` now validates source SHA256 in addition to binary.

### Fixed
- Closed the artifact integrity gap: both `.c` and `.so` are now tracked.
- Removed final stale claims about unavailable plugin source.

### Known Gaps
- Source compilation and binary re-generation still to be validated on a VM with GCC/ATS build environment.
- Full end-to-end install with `install-ats-proxy.sh` still needs VM validation.

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

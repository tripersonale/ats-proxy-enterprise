# Artifact Manifest

## Runtime Artifacts

| Artifact | Path | Status | Hash |
|----------|------|--------|------|
| Plugin binary v2.1 | `bin/ats_proxy_filter_v21.so` | Versioned and tested | SHA256 `26c4371d0c32377498afeb80eb874a11bed2ac8c749c600073356bb3c2087674` |
| Plugin C source v2.1 | `src/ats_proxy_filter_v21.c` | Versioned and tested | SHA256 `ac742e549c3081af44c320117ce0a8a1e8d9b80dbb76327f154e7d0797a7ffea` |
| Plugin binary v3.0 beta | `bin/ats_proxy_filter_v30.so` | Built and mode-tested on VM137 ATS 10.1.2 | SHA256 `157b97f85ab9524d2cac978c8c27df79cdaa64c0b9d4dc5590fede9123df4502` |
| Plugin C source v3.0 beta | `src/ats_proxy_filter_v30.c` | Versioned and mode-tested on VM137 ATS 10.1.2 | SHA256 `05e93d43bf0d0ff8b75dee59c06a3932b3ef79e5d05e83efa72276476f6bf1ae` |
| Installer | `scripts/install-ats-proxy.sh` | End-to-end tested 24.04/26.04 | Tracked by Git |
| Regression test | `scripts/ats-regression-test.sh` | Tested 24.04/26.04 | Tracked by Git |
| Hardening check | `scripts/ats-hardening-check.sh` | Tested 24.04/26.04 | Tracked by Git |
| v3.0 config CLI | `scripts/ats-ctl` | Tested locally and on VM137 | SHA256 `eb8b19e386609bdf0d54d23c75d71abfe10694e99002a30b8b4f8e4ed1d9ed3d` |
| v3.0 plugin build script | `scripts/compile-plugin.sh` | Built v3 plugin on VM137 ATS 10.1.2 | SHA256 `756de6897ac02ab3e83a7007ee3215fa0fc0582930f387ba1759ffd2b618882e` |
| v3.0 mode test | `scripts/ats-mode-test.sh` | 5/5 modes passed on VM137 ATS 10.1.2 | SHA256 `c45afb680764b00e7aaef8d1dcb666c7e3231ed12ea0e3bc02c17a9f71e66fad` |

## Provenance

- Original plugin binary recovered read-only from VM130 and VM134 disks via Proxmox/libguestfs.
- Previous recovered binary SHA256: `6a1a73ff015ced9d6d35631fecf318d860bfbbf59b6066dcb3eecb8490d8f9c7`.
- Current official binary was rebuilt from `src/ats_proxy_filter_v21.c` and validated on ATS 9.2.13.
- Plugin v3.0 beta binary was built on VM137 Ubuntu 26.04 against ATS 10.1.2 generated headers and installed libraries.
- ATS source tarball is verified by SHA512 in `scripts/install-ats-proxy.sh`.

## Validation Summary

| Target | Build/Install | Regression | Hardening |
|--------|---------------|------------|-----------|
| VM135 Ubuntu 24.04.4 | Installer OK | 9/9 OK | 25/25 OK |
| VM136 Ubuntu 26.04 | Installer OK | 9/9 OK | 25/25 OK |
| VM137 Ubuntu 26.04 + ATS 10.1.2 | Manual L0 build OK, plugin v3 build OK | v3 mode tests 11/11 OK | Not applied |

## Policy

- A required runtime artifact must be tracked in Git or documented here with explicit provenance and hash.
- Documentation must not claim an artifact exists unless `scripts/check-repo-consistency.sh` can verify it.
- Binary-only artifacts are temporary exceptions; source is required for maintainability.
- Any new plugin binary must update this file, `TEST_MATRIX.md`, and `CHANGELOG.md` after real VM tests.

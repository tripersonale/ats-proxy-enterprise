# Artifact Manifest

## Runtime Artifacts

| Artifact | Path | Status | Hash |
|----------|------|--------|------|
| Plugin binary v2.1 | `bin/ats_proxy_filter_v21.so` | Versioned and tested | SHA256 `26c4371d0c32377498afeb80eb874a11bed2ac8c749c600073356bb3c2087674` |
| Plugin C source v2.1 | `src/ats_proxy_filter_v21.c` | Versioned and tested | SHA256 `ac742e549c3081af44c320117ce0a8a1e8d9b80dbb76327f154e7d0797a7ffea` |
| Installer | `scripts/install-ats-proxy.sh` | End-to-end tested 24.04/26.04 | Tracked by Git |
| Regression test | `scripts/ats-regression-test.sh` | Tested 24.04/26.04 | Tracked by Git |
| Hardening check | `scripts/ats-hardening-check.sh` | Tested 24.04/26.04 | Tracked by Git |

## Provenance

- Original plugin binary recovered read-only from VM130 and VM134 disks via Proxmox/libguestfs.
- Previous recovered binary SHA256: `6a1a73ff015ced9d6d35631fecf318d860bfbbf59b6066dcb3eecb8490d8f9c7`.
- Current official binary was rebuilt from `src/ats_proxy_filter_v21.c` and validated on ATS 9.2.13.
- ATS source tarball is verified by SHA512 in `scripts/install-ats-proxy.sh`.

## Validation Summary

| Target | Build/Install | Regression | Hardening |
|--------|---------------|------------|-----------|
| VM135 Ubuntu 24.04.4 | Installer OK | 9/9 OK | 25/25 OK |
| VM136 Ubuntu 26.04 | Installer OK | 9/9 OK | 25/25 OK |

## Policy

- A required runtime artifact must be tracked in Git or documented here with explicit provenance and hash.
- Documentation must not claim an artifact exists unless `scripts/check-repo-consistency.sh` can verify it.
- Binary-only artifacts are temporary exceptions; source is required for maintainability.
- Any new plugin binary must update this file, `TEST_MATRIX.md`, and `CHANGELOG.md` after real VM tests.

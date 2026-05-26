# Artifact Manifest - ATS Proxy Enterprise

## Required Runtime Artifacts

| Artifact | Path | Status | Source |
|----------|------|--------|--------|
| Plugin binary v2.1 | `bin/ats_proxy_filter_v21.so` | Versioned | Recovered read-only from VM130 and VM134 disks via Proxmox/libguestfs |
| Plugin C source v2.1 | `src/ats_proxy_filter_v21.c` | Versioned | Compiled and tested 2026-05-26 on VM135 (ATS 9.2.13, Ubuntu 24.04). Full equivalence verified. |

## Plugin Binary v2.1

Path:

```text
bin/ats_proxy_filter_v21.so
```

Rebuilt from source on 2026-05-26.

Identity:

```text
SHA256: 26c4371d0c32377498afeb80eb874a11bed2ac8c749c600073356bb3c2087674
file: ELF 64-bit LSB shared object, x86-64, dynamically linked, not stripped
```

Previous recovered binary (deprecated):
```text
SHA256: 6a1a73ff015ced9d6d35631fecf318d860bfbbf59b6066dcb3eecb8490d8f9c7 (VM130/VM134 original)
```

Validation:
- Source compiled successfully on ATS 9.2.13 (Ubuntu 24.04 VM135, GCC 13.x) and 26.04 (VM136, GCC 15.x).
- Full test battery passed on both OS versions: DENY 403 "Forbidden", WHITELIST pass, AUTH missing 407 + Proxy-Authenticate, AUTH valid pass, AUTH wrong 407.
- 50 concurrent DENY requests all returned 403 with zero failures.
- Source compiles cleanly; only deprecation warnings for `TSUserArgGet/Set` (safe, same API as original ATS 9.2.13 example plugins).

## Source-Code Status

Source was reconstructed on 2026-05-25, API-corrected and compiled on 2026-05-26. Functional equivalence verified: full test battery matches documented behavior on both Ubuntu 24.04 and 26.04.

## Policy

- Every required runtime artifact must be tracked or explicitly documented in this manifest.
- Documentation must not refer to a required file as available unless `scripts/check-repo-consistency.sh` can verify it.
- Binary artifacts are acceptable only with provenance, hash and test status.
- Source code is preferred and required before declaring the plugin fully maintainable.

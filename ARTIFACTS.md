# Artifact Manifest - ATS Proxy Enterprise

## Required Runtime Artifacts

| Artifact | Path | Status | Source |
|----------|------|--------|--------|
| Plugin binary v2.1 | `bin/ats_proxy_filter_v21.so` | Versioned | Recovered read-only from VM130 and VM134 disks via Proxmox/libguestfs |
| Plugin C source v2.1 | `src/ats_proxy_filter_v21.c` | Versioned | Reconstructed 2026-05-25 from documented behavior and ATS basic_auth.c base |

## Plugin Binary v2.1

Path:

```text
bin/ats_proxy_filter_v21.so
```

Recovered from:

```text
VM130: /opt/trafficserver/lib/modules/ats_proxy_filter.so
VM134: /opt/trafficserver/lib/modules/ats_proxy_filter.so
```

Recovery method:

```text
Proxmox host, read-only libguestfs/virt-cat against VM disks.
No guest SSH and no guest filesystem modification.
```

Identity:

```text
SHA256: 6a1a73ff015ced9d6d35631fecf318d860bfbbf59b6066dcb3eecb8490d8f9c7
BuildID: f6c18c6d9b27dd58d9e23a8de8685c442d748b19
file: ELF 64-bit LSB shared object, x86-64, dynamically linked, not stripped
```

Validation:
- VM130 and VM134 binaries are byte-identical.
- `scripts/preflight.sh` passes with `ATS_PLUGIN_PATH=./bin/ats_proxy_filter_v21.so`.
- `scripts/install-ats-proxy.sh --validate-only` passes with the versioned binary.

## Source-Code Gap

The source was reconstructed on 2026-05-25 from documented behavior, ATS `basic_auth.c` example, and the operational knowledge captured in `PROJECT_ARCHIVE.md`. The binary compiled from this source must be validated against the legacy binary recovered from VM130/VM134 before declaring full equivalence.

## Policy

- Every required runtime artifact must be tracked or explicitly documented in this manifest.
- Documentation must not refer to a required file as available unless `scripts/check-repo-consistency.sh` can verify it.
- Binary artifacts are acceptable only with provenance, hash and test status.
- Source code is preferred and required before declaring the plugin fully maintainable.

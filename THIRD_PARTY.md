# Third-Party Components and Attribution

ATS Proxy Enterprise includes and depends on the following third-party software.
Their licenses are separate and independent from the FEL-1.0 license that
covers the ATS Proxy Enterprise plugin, scripts, and documentation.

## Apache Traffic Server 9.2.13

- **License**: Apache License 2.0
- **Copyright**: The Apache Software Foundation
- **Homepage**: https://trafficserver.apache.org
- **Note**: This project is NOT affiliated with, endorsed by, or sponsored by
  The Apache Software Foundation. "Apache", "Apache Traffic Server", and the
  Apache feather logo are trademarks of The Apache Software Foundation.
  We use the name "ATS" descriptively to indicate compatibility.

ATS Proxy Enterprise distributes a precompiled binary of Apache Traffic Server
in the `ats-core` Debian package. The source code of Apache Traffic Server is
available at https://trafficserver.apache.org/download.

## PCRE - Perl Compatible Regular Expressions 8.45

- **License**: BSD
- **Copyright**: University of Cambridge
- **Homepage**: https://www.pcre.org

## What we built (FEL-1.0)

The following components are original work, licensed under the
Fair Enterprise License v1.0 (FEL-1.0):

- `src/ats_proxy_filter_v30.c` — URL filtering and authentication plugin
- `scripts/ats-ctl` — command-line policy management tool
- `scripts/ats-mode-test.sh` — automated mode testing
- `scripts/compile-plugin.sh` — repeatable plugin build
- `scripts/ats-hardening-check.sh` — 25-point hardening verification
- `scripts/apply-ats-hardening-v3.sh` — hardening applicator
- All configuration templates in `config/`
- All documentation in `GUIDE/`
- All man pages in `man/`

The plugin uses only the documented public API of Apache Traffic Server
(`<ts/ts.h>`, `<ts/remap.h>`) and does not contain any code copied from
Apache Traffic Server.

## OpenSSL

- **License**: Apache License 2.0 (OpenSSL 3.x)
- Used by the plugin for SHA-256 password hashing (EVP interface).

---

Last updated: 2026-05-28

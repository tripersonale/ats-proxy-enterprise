# Manifesto Principi - ATS Proxy Enterprise

Documento corrente ricreato in root. README contiene il manifesto breve; qui sono esplicitati i principi operativi.

1. **Replicabilita prima delle promesse**: un claim e valido solo se testato o marcato non validato.
2. **Artifact completi**: sorgente, binario, hash, script e test devono essere versionati.
3. **Defense in depth**: UFW, `ip_allow.yaml`, plugin policy, auth, fail2ban e systemd sandbox.
4. **Least privilege**: servizio `ats`, shell nologin, permessi `640` sulle config.
5. **Config esterna**: utenti, admin, deny e whitelist stanno in file, non hardcoded.
6. **Rollback possibile**: backup, etckeeper e artifact hash.
7. **Compliance pragmatica**: DPIA/registro trattamenti devono riflettere log reali.
8. **Upgrade solo con laboratorio**: ATS 10.x non e produzione finche non passa test.
9. **No segreti in Git**: password e chiavi fuori repo.
10. **Miglioramento continuo**: ogni gap va in `IMPROVEMENTS.md` o `TEST_MATRIX.md`.

Stato 0.13.0: installer/regression/hardening validati su Ubuntu 24.04 e 26.04.

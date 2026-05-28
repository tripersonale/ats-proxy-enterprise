/*
 * ats_proxy_filter_v30.c
 *
 * Cosa fa:
 *   Plugin Apache Traffic Server per forward proxy con modalita OFF, deny-only,
 *   whitelist-only, auth-all e auth-non-deny.
 *
 * Come si usa:
 *   Compilare contro gli header ATS e caricare il .so in plugin.config.
 *   La configurazione vive in /etc/ats-proxy/filter.conf con INCLUDE verso
 *   deny.list, whitelist.list, admin.list e auth.conf.
 *
 * Perche esiste:
 *   Sostituisce il modello v2.x monolitico con un plugin unico ma spegnibile e
 *   governabile per livelli, senza password in chiaro nei file di configurazione.
 *
 * Dipendenze:
 *   Apache Traffic Server headers, OpenSSL libcrypto per SHA-256.
 *
 * Variabili/file richiesti:
 *   /etc/ats-proxy/filter.conf oppure <TSConfigDir>/ats-proxy/filter.conf.
 *
 * Rischi:
 *   HTTP Basic Auth protegge le credenziali solo se il canale client-proxy e TLS
 *   o rete fidata. Le password a riposo sono hashate con salt.
 *
 * Rollback:
 *   Rimuovere il plugin da plugin.config o impostare MODE off e riavviare ATS.
 *
 * TEST:
 *   Verificare ogni MODE con scripts/ats-mode-test.sh su VM ATS 9 e ATS 10.
 */

#include <ts/ts.h>
#include <ts/remap.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <openssl/evp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEFAULT_CFG_DIR "/opt/trafficserver/etc/trafficserver/plugin"
#define MAX_ADMIN 64
#define MAX_DENY 512
#define MAX_WHITE 512
#define MAX_USERS 256
#define MAX_LINE 1024
#define MAX_DEPTH 8

#ifdef __cplusplus
#define ATS_EVENT_FUNC(fn) reinterpret_cast<TSEventFunc>(fn)
#define ATS_TXN(ptr) reinterpret_cast<TSHttpTxn>(ptr)
#define ATS_STATUS_FROM_ARG(ptr) static_cast<int>(reinterpret_cast<intptr_t>(ptr))
#define ATS_ARG_FROM_STATUS(status) reinterpret_cast<void *>(static_cast<intptr_t>(status))
extern "C" void TSPluginInit(int argc, const char *argv[]);
#else
#define ATS_EVENT_FUNC(fn) (TSEventFunc)(fn)
#define ATS_TXN(ptr) (TSHttpTxn)(ptr)
#define ATS_STATUS_FROM_ARG(ptr) (int)(long)(ptr)
#define ATS_ARG_FROM_STATUS(status) (void *)(long)(status)
#endif

typedef enum {
  MODE_OFF = 0,
  MODE_DENY,
  MODE_WHITELIST,
  MODE_AUTH_ALL,
  MODE_AUTH_ND
} filter_mode_t;

static filter_mode_t mode = MODE_OFF;
static char admin_ips[MAX_ADMIN][64];
static int admin_cnt = 0;
static char deny_r[MAX_DENY][256];
static int deny_cnt = 0;
static char white_r[MAX_WHITE][256];
static int white_cnt = 0;
static char users[MAX_USERS][64];
static char salts[MAX_USERS][64];
static char hashes[MAX_USERS][65];
static int users_cnt = 0;
static int arg_idx = -1;

static int handle_response(TSCont contp, TSEvent event, void *edata);

static void trim(char *s) {
  size_t len;
  while (*s == ' ' || *s == '\t') memmove(s, s + 1, strlen(s));
  len = strlen(s);
  while (len > 0 && (s[len - 1] == '\n' || s[len - 1] == '\r' || s[len - 1] == ' ' || s[len - 1] == '\t')) {
    s[len - 1] = '\0';
    len--;
  }
}

static int b64_decode(const char *in, size_t ilen, char *out, size_t olen) {
  static const char T[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  int i, j;
  unsigned char d[4];
  size_t opos = 0;
  if (ilen % 4 != 0 || olen == 0) return 0;
  for (i = 0; i < (int)ilen; i += 4) {
    for (j = 0; j < 4; j++) {
      char c = in[i + j];
      if (c == '=') { d[j] = 0; continue; }
      const char *p = strchr(T, c);
      if (!p) return 0;
      d[j] = (unsigned char)(p - T);
    }
    for (j = 0; j < 3; j++) {
      unsigned char v;
      if (j == 0) v = (unsigned char)((d[0] << 2) | (d[1] >> 4));
      else if (j == 1) v = (unsigned char)(((d[1] & 0x0F) << 4) | (d[2] >> 2));
      else v = (unsigned char)(((d[2] & 0x03) << 6) | d[3]);
      if (opos < olen - 1) out[opos++] = (char)v;
    }
    if (in[i + 2] == '=' || in[i + 3] == '=') break;
  }
  out[opos] = '\0';
  return 1;
}

static int safe_eq(const char *a, const char *b) {
  size_t la = strlen(a), lb = strlen(b), max = la > lb ? la : lb;
  unsigned char diff = (unsigned char)(la ^ lb);
  for (size_t i = 0; i < max; i++) {
    unsigned char ca = i < la ? (unsigned char)a[i] : 0;
    unsigned char cb = i < lb ? (unsigned char)b[i] : 0;
    diff |= (unsigned char)(ca ^ cb);
  }
  return diff == 0;
}

static void sha256_hex(const char *salt, const char *pass, char out[65]) {
  EVP_MD_CTX *ctx = EVP_MD_CTX_new();
  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned int digest_len = 0;
  if (!ctx) {
    out[0] = '\0';
    return;
  }
  EVP_DigestInit_ex(ctx, EVP_sha256(), NULL);
  EVP_DigestUpdate(ctx, salt, strlen(salt));
  EVP_DigestUpdate(ctx, pass, strlen(pass));
  EVP_DigestFinal_ex(ctx, digest, &digest_len);
  EVP_MD_CTX_free(ctx);
  if (digest_len != 32) {
    out[0] = '\0';
    return;
  }
  for (unsigned int i = 0; i < digest_len; i++) snprintf(out + (i * 2), 3, "%02x", digest[i]);
  out[64] = '\0';
}

static int authorized(const char *user, const char *pass) {
  char computed[65];
  for (int i = 0; i < users_cnt; i++) {
    if (!strcmp(users[i], user)) {
      sha256_hex(salts[i], pass, computed);
      return safe_eq(computed, hashes[i]);
    }
  }
  return 0;
}

static int host_match(const char *host, const char *pattern) {
  return strstr(pattern, ".*") ? (strstr(host, pattern + 2) != NULL) : !strcmp(host, pattern);
}

static int list_match(const char *host, char list[][256], int count) {
  for (int i = 0; i < count; i++) if (host_match(host, list[i])) return 1;
  return 0;
}

static int ip_is_admin(const char *ip) {
  for (int i = 0; i < admin_cnt; i++) if (!strcmp(admin_ips[i], ip)) return 1;
  return 0;
}

static void add_admin(const char *v) {
  if (admin_cnt < MAX_ADMIN) snprintf(admin_ips[admin_cnt++], sizeof(admin_ips[0]), "%s", v);
}

static void add_deny(const char *v) {
  if (deny_cnt < MAX_DENY) snprintf(deny_r[deny_cnt++], sizeof(deny_r[0]), "%s", v);
}

static void add_white(const char *v) {
  if (white_cnt < MAX_WHITE) snprintf(white_r[white_cnt++], sizeof(white_r[0]), "%s", v);
}

static void add_user(const char *user, const char *salt_hash) {
  char tmp[160];
  char *sep;
  if (users_cnt >= MAX_USERS) return;
  snprintf(tmp, sizeof(tmp), "%s", salt_hash);
  sep = strchr(tmp, '$');
  if (!sep) {
    TSError("[ats_proxy_filter_v30] invalid USER entry for %s: expected salt$sha256", user);
    return;
  }
  *sep = '\0';
  sep++;
  if (strlen(sep) != 64) {
    TSError("[ats_proxy_filter_v30] invalid USER hash length for %s", user);
    return;
  }
  if (strlen(tmp) >= sizeof(salts[0])) {
    TSError("[ats_proxy_filter_v30] invalid USER salt length for %s", user);
    return;
  }
  snprintf(users[users_cnt], sizeof(users[0]), "%s", user);
  memcpy(salts[users_cnt], tmp, strlen(tmp) + 1);
  memcpy(hashes[users_cnt], sep, 65);
  users_cnt++;
}

static void set_mode(const char *v) {
  if (!strcmp(v, "off")) mode = MODE_OFF;
  else if (!strcmp(v, "deny")) mode = MODE_DENY;
  else if (!strcmp(v, "whitelist")) mode = MODE_WHITELIST;
  else if (!strcmp(v, "auth_all")) mode = MODE_AUTH_ALL;
  else if (!strcmp(v, "auth_nd")) mode = MODE_AUTH_ND;
  else TSError("[ats_proxy_filter_v30] unknown MODE '%s', keeping previous mode", v);
}

static int infer_include_type(const char *path) {
  if (strstr(path, "deny")) return 1;
  if (strstr(path, "whitelist")) return 2;
  if (strstr(path, "admin")) return 3;
  return 0;
}

static void load_file(const char *path, int default_type, int depth);

static void parse_line(char *line, int default_type, int depth) {
  char cmd[64], v1[512], v2[512];
  int n;
  trim(line);
  if (line[0] == '#' || line[0] == '\0') return;
  cmd[0] = v1[0] = v2[0] = '\0';
  n = sscanf(line, "%63s %511s %511s", cmd, v1, v2);
  if (n <= 0) return;

  if (!strcmp(cmd, "MODE") && n >= 2) set_mode(v1);
  else if (!strcmp(cmd, "MODE=") && n >= 2) set_mode(v1);
  else if (!strncmp(cmd, "MODE=", 5)) set_mode(cmd + 5);
  else if (!strcmp(cmd, "ADMIN") && n >= 2) add_admin(v1);
  else if (!strcmp(cmd, "DENY") && n >= 2) add_deny(v1);
  else if (!strcmp(cmd, "WHITELIST") && n >= 2) add_white(v1);
  else if (!strcmp(cmd, "USER") && n >= 3) add_user(v1, v2);
  else if (!strcmp(cmd, "INCLUDE") && n >= 2) {
    if (n >= 3) {
      int t = !strcmp(v1, "deny") ? 1 : !strcmp(v1, "whitelist") ? 2 : !strcmp(v1, "admin") ? 3 : 0;
      load_file(v2, t, depth + 1);
    } else {
      load_file(v1, infer_include_type(v1), depth + 1);
    }
  } else if (default_type == 1) add_deny(cmd);
  else if (default_type == 2) add_white(cmd);
  else if (default_type == 3) add_admin(cmd);
  else TSError("[ats_proxy_filter_v30] ignored config line: %s", line);
}

static void load_file(const char *path, int default_type, int depth) {
  FILE *f;
  char line[MAX_LINE];
  if (depth > MAX_DEPTH) {
    TSError("[ats_proxy_filter_v30] include depth exceeded at %s", path);
    return;
  }
  f = fopen(path, "r");
  if (!f) {
    TSError("[ats_proxy_filter_v30] cannot open config: %s", path);
    return;
  }
  while (fgets(line, sizeof(line), f)) parse_line(line, default_type, depth);
  fclose(f);
}

static void load_cfg(void) {
  char cfg_path[512];
  snprintf(cfg_path, sizeof(cfg_path), "%s/filter.conf", DEFAULT_CFG_DIR);
  load_file(cfg_path, 0, 0);
  TSError("[ats_proxy_filter_v30] loaded: mode=%d admin=%d deny=%d whitelist=%d users=%d",
    mode, admin_cnt, deny_cnt, white_cnt, users_cnt);
}

static int request_is_authorized(TSMBuffer bufp, TSMLoc hdr_loc, const char *client_ip, const char *host_copy) {
  const char *auth_hdr = NULL;
  TSMLoc auth_field_loc = TSMimeHdrFieldFind(bufp, hdr_loc, TS_MIME_FIELD_PROXY_AUTHORIZATION, TS_MIME_LEN_PROXY_AUTHORIZATION);
  if (auth_field_loc != TS_NULL_MLOC) {
    int avlen = 0;
    auth_hdr = TSMimeHdrFieldValueStringGet(bufp, hdr_loc, auth_field_loc, -1, &avlen);
    if (auth_hdr && avlen > 6 && !strncmp(auth_hdr, "Basic ", 6)) {
      char decoded[256];
      if (b64_decode(auth_hdr + 6, (size_t)(avlen - 6), decoded, sizeof(decoded))) {
        char *colon = strchr(decoded, ':');
        if (colon) {
          *colon = '\0';
          if (authorized(decoded, colon + 1)) {
            TSError("[ats_proxy_filter_v30] AUTH OK user=%s host=%s", decoded, host_copy);
            TSHandleMLocRelease(bufp, hdr_loc, auth_field_loc);
            return 1;
          }
          TSError("[ats_proxy_filter_v30] AUTH FAIL user=%s from=%s", decoded, client_ip);
        }
      }
    }
    TSHandleMLocRelease(bufp, hdr_loc, auth_field_loc);
  }
  return 0;
}

static int send_error(TSHttpTxn txnp, int status) {
  TSHttpTxnHookAdd(txnp, TS_HTTP_SEND_RESPONSE_HDR_HOOK, TSContCreate(ATS_EVENT_FUNC(handle_response), NULL));
  TSUserArgSet(txnp, arg_idx, ATS_ARG_FROM_STATUS(status));
  TSHttpTxnReenable(txnp, TS_EVENT_HTTP_ERROR);
  return 0;
}

static int handle_dns(TSCont contp, TSEvent event, void *edata) {
  (void)contp;
  TSHttpTxn txnp = ATS_TXN(edata);
  TSMBuffer bufp;
  TSMLoc hdr_loc, field_loc;
  const char *host;
  char host_copy[256];
  char client_ip[128] = "?";
  int denied, whitelisted, authed;

  if (event != TS_EVENT_HTTP_OS_DNS || mode == MODE_OFF) {
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
    return 0;
  }
  if (TSHttpTxnClientReqGet(txnp, &bufp, &hdr_loc) != TS_SUCCESS) {
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
    return 0;
  }
  field_loc = TSMimeHdrFieldFind(bufp, hdr_loc, TS_MIME_FIELD_HOST, TS_MIME_LEN_HOST);
  if (field_loc == TS_NULL_MLOC) {
    TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
    return 0;
  }
  int vlen = 0;
  host = TSMimeHdrFieldValueStringGet(bufp, hdr_loc, field_loc, -1, &vlen);
  if (!host || vlen == 0) {
    TSHandleMLocRelease(bufp, hdr_loc, field_loc);
    TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
    return 0;
  }
  int copy_len = vlen < (int)sizeof(host_copy) - 1 ? vlen : (int)sizeof(host_copy) - 1;
  memcpy(host_copy, host, (size_t)copy_len);
  host_copy[copy_len] = '\0';
  TSHandleMLocRelease(bufp, hdr_loc, field_loc);

  struct sockaddr const *client_addr = TSHttpTxnClientAddrGet(txnp);
  if (client_addr) {
    if (client_addr->sa_family == AF_INET) {
      const struct sockaddr_in *sin = (const struct sockaddr_in *)client_addr;
      inet_ntop(AF_INET, &sin->sin_addr, client_ip, sizeof(client_ip));
    } else if (client_addr->sa_family == AF_INET6) {
      const struct sockaddr_in6 *sin6 = (const struct sockaddr_in6 *)client_addr;
      inet_ntop(AF_INET6, &sin6->sin6_addr, client_ip, sizeof(client_ip));
    }
  }

  if (ip_is_admin(client_ip)) {
    TSError("[ats_proxy_filter_v30] ADMIN bypass from=%s host=%s", client_ip, host_copy);
    TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
    return 0;
  }

  denied = list_match(host_copy, deny_r, deny_cnt);
  whitelisted = list_match(host_copy, white_r, white_cnt);
  authed = request_is_authorized(bufp, hdr_loc, client_ip, host_copy);
  TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);

  if (mode == MODE_DENY) {
    if (denied) return send_error(txnp, TS_HTTP_STATUS_FORBIDDEN);
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
    return 0;
  }
  if (mode == MODE_WHITELIST) {
    if (whitelisted) {
      TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
      return 0;
    }
    return send_error(txnp, TS_HTTP_STATUS_FORBIDDEN);
  }
  if (mode == MODE_AUTH_ALL) {
    if (authed) {
      TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
      return 0;
    }
    return send_error(txnp, TS_HTTP_STATUS_PROXY_AUTHENTICATION_REQUIRED);
  }
  if (mode == MODE_AUTH_ND) {
    if (denied) return send_error(txnp, TS_HTTP_STATUS_FORBIDDEN);
    if (whitelisted || authed) {
      TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
      return 0;
    }
    return send_error(txnp, TS_HTTP_STATUS_PROXY_AUTHENTICATION_REQUIRED);
  }

  TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
  return 0;
}

static int handle_response(TSCont contp, TSEvent event, void *edata) {
  (void)contp;
  (void)event;
  TSHttpTxn txnp = ATS_TXN(edata);
  TSMBuffer bufp;
  TSMLoc hdr_loc;
  if (TSHttpTxnClientRespGet(txnp, &bufp, &hdr_loc) != TS_SUCCESS) return 0;
  int status = TS_HTTP_STATUS_OK;
  void *arg = TSUserArgGet(txnp, arg_idx);
  if (arg) status = ATS_STATUS_FROM_ARG(arg);
  TSHttpHdrStatusSet(bufp, hdr_loc, (TSHttpStatus)status);
  if (status == TS_HTTP_STATUS_FORBIDDEN) {
    TSHttpHdrReasonSet(bufp, hdr_loc, "Forbidden", -1);
  } else if (status == TS_HTTP_STATUS_PROXY_AUTHENTICATION_REQUIRED) {
    TSMLoc field_loc;
    if (TSMimeHdrFieldCreate(bufp, hdr_loc, &field_loc) == TS_SUCCESS) {
      TSMimeHdrFieldNameSet(bufp, hdr_loc, field_loc, TS_MIME_FIELD_PROXY_AUTHENTICATE, TS_MIME_LEN_PROXY_AUTHENTICATE);
      TSMimeHdrFieldValueStringInsert(bufp, hdr_loc, field_loc, -1, "Basic realm=\"ATS Proxy\"", -1);
      TSMimeHdrFieldAppend(bufp, hdr_loc, field_loc);
      TSHandleMLocRelease(bufp, hdr_loc, field_loc);
    }
  }
  TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
  TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
  return 0;
}

static int auth_plugin(TSCont contp, TSEvent event, void *edata) {
  if (event == TS_EVENT_HTTP_OS_DNS) return handle_dns(contp, event, edata);
  if (event == TS_EVENT_HTTP_SEND_RESPONSE_HDR) return handle_response(contp, event, edata);
  TSHttpTxnReenable(ATS_TXN(edata), TS_EVENT_HTTP_CONTINUE);
  return 0;
}

void TSPluginInit(int argc, const char *argv[]) {
  (void)argc;
  (void)argv;
  TSPluginRegistrationInfo info;
  info.plugin_name = "ats_proxy_filter_v30";
  info.vendor_name = "ATS Proxy Enterprise";
  info.support_email = "proxy@tripersonale.org";
  if (TSPluginRegister(&info) != TS_SUCCESS) {
    TSError("[ats_proxy_filter_v30] plugin registration failed");
    return;
  }
  if (TSUserArgIndexReserve(TS_USER_ARGS_TXN, "ats_proxy_filter_v30", "filter action", &arg_idx) != TS_SUCCESS) {
    TSError("[ats_proxy_filter_v30] cannot reserve txn arg");
    return;
  }
  load_cfg();
  TSCont contp = TSContCreate(ATS_EVENT_FUNC(auth_plugin), NULL);
  TSHttpHookAdd(TS_HTTP_OS_DNS_HOOK, contp);
  TSError("[ats_proxy_filter_v30] plugin loaded, arg_idx=%d", arg_idx);
}

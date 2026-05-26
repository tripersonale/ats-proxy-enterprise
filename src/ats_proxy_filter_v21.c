#include <ts/ts.h>
#include <ts/remap.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define CFG_PATH "/etc/trafficserver/ats_proxy_filter.conf"
#define MAX_ADMIN 16
#define MAX_DENY 64
#define MAX_WHITE 64
#define MAX_USERS 64
#define MAX_LINE 512

static char admin_ips[MAX_ADMIN][64];
static int admin_cnt = 0;

static char deny_r[MAX_DENY][256];
static int deny_cnt = 0;

static char white_r[MAX_WHITE][256];
static int white_cnt = 0;

static char users[MAX_USERS][64];
static char passes[MAX_USERS][64];
static int users_cnt = 0;

static int arg_idx = -1;

static int b64_decode(const char *in, size_t ilen, char *out, size_t olen) {
  static const char T[64] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  int i, j, k;
  unsigned char d[4];
  size_t opos = 0;
  if (ilen % 4 != 0) return 0;
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
      if (j == 0)      v = (d[0] << 2) | (d[1] >> 4);
      else if (j == 1) v = ((d[1] & 0x0F) << 4) | (d[2] >> 2);
      else             v = ((d[2] & 0x03) << 6) | d[3];
      if (opos < olen - 1) out[opos++] = (char)v;
    }
    if (in[i+2] == '=' || in[i+3] == '=') break;
  }
  out[opos] = '\0';
  return 1;
}

static int authorized(const char *user, const char *pass) {
  for (int i = 0; i < users_cnt; i++) {
    if (!strcmp(users[i], user) && !strcmp(passes[i], pass)) return 1;
  }
  return 0;
}

static int host_match(const char *host, const char *pattern) {
  return strstr(pattern, ".*") ? (strstr(host, pattern + 2) != NULL) : !strcmp(host, pattern);
}

static int ip_is_admin(const char *ip) {
  for (int i = 0; i < admin_cnt; i++) {
    if (!strcmp(admin_ips[i], ip)) return 1;
  }
  return 0;
}

static const char *get_client_ip(TSHttpTxn txnp) {
  TSMBuffer bufp;
  TSMLoc hdr_loc, field_loc;
  if (TSHttpTxnClientReqGet(txnp, &bufp, &hdr_loc) != TS_SUCCESS) return NULL;
  if (TSMimeHdrFieldFind(bufp, hdr_loc, TS_MIME_FIELD_CLIENT_IP, TS_MIME_LEN_CLIENT_IP, &field_loc) != TS_SUCCESS) {
    TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
    return NULL;
  }
  int vlen = 0;
  const char *val = TSMimeHdrFieldValueStringGet(bufp, hdr_loc, field_loc, -1, &vlen);
  static char ip[64];
  if (val && vlen > 0 && vlen < (int)sizeof(ip)) {
    memcpy(ip, val, vlen);
    ip[vlen] = '\0';
  } else {
    TSHandleMLocRelease(bufp, hdr_loc, field_loc);
    TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
    return NULL;
  }
  TSHandleMLocRelease(bufp, hdr_loc, field_loc);
  TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
  return ip;
}

static void handle_response(TSCont contp, TSEvent event, void *edata) {
  TSHttpTxn txnp = (TSHttpTxn)edata;
  TSMBuffer bufp;
  TSMLoc hdr_loc;

  if (TSHttpTxnClientRespGet(txnp, &bufp, &hdr_loc) != TS_SUCCESS) return;

  int status = 200;
  void *arg = TSHttpTxnArgGet(txnp, arg_idx);
  if (arg) status = (int)(long)arg;

  TSHttpHdrStatusSet(bufp, hdr_loc, (TSHttpStatus)status);

  if (status == 407 || status == TS_HTTP_STATUS_PROXY_AUTHENTICATION_REQUIRED) {
    TSMLoc field_loc;
    if (TSMimeHdrFieldCreate(bufp, hdr_loc, &field_loc) == TS_SUCCESS) {
      TSMimeHdrFieldNameSet(bufp, hdr_loc, field_loc, TS_MIME_FIELD_PROXY_AUTHENTICATE, TS_MIME_LEN_PROXY_AUTHENTICATE);
      TSMimeHdrFieldValueStringSet(bufp, hdr_loc, field_loc, -1, "Basic realm=\"ATS Proxy\"");
      TSMimeHdrFieldAppend(bufp, hdr_loc, field_loc);
      TSHandleMLocRelease(bufp, hdr_loc, field_loc);
    }
  } else if (status == 403) {
    TSMLoc field_loc;
    if (TSMimeHdrFieldCreate(bufp, hdr_loc, &field_loc) == TS_SUCCESS) {
      TSMimeHdrFieldNameSet(bufp, hdr_loc, field_loc, "Reason", 6);
      TSMimeHdrFieldValueStringSet(bufp, hdr_loc, field_loc, -1, "Forbidden");
      TSMimeHdrFieldAppend(bufp, hdr_loc, field_loc);
      TSHandleMLocRelease(bufp, hdr_loc, field_loc);
    }
  }

  TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
  TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
}

static int handle_dns(TSCont contp, TSEvent event, void *edata) {
  TSHttpTxn txnp = (TSHttpTxn)edata;
  TSMBuffer bufp;
  TSMLoc hdr_loc, url_loc, host_field_loc;
  const char *host_val;
  int host_len = 0;
  int is_denied = 0, is_whitelisted = 0;

  if (event != TS_EVENT_HTTP_OS_DNS) {
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
    return 0;
  }

  if (TSHttpTxnClientReqGet(txnp, &bufp, &hdr_loc) != TS_SUCCESS) {
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
    return 0;
  }

  if (TSHttpTxnPristineUrlGet(txnp, &url_loc) != TS_SUCCESS) {
    TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
    return 0;
  }

  host_val = TSUrlHostGet(bufp, url_loc, &host_len);
  if (!host_val || host_len == 0) {
    TSHandleMLocRelease(bufp, url_loc, TS_NULL_MLOC);
    TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
    return 0;
  }

  char host[256];
  int copy_len = host_len < (int)sizeof(host) - 1 ? host_len : (int)sizeof(host) - 1;
  memcpy(host, host_val, copy_len);
  host[copy_len] = '\0';

  TSHandleMLocRelease(bufp, url_loc, TS_NULL_MLOC);

  const char *client_ip = get_client_ip(txnp);
  if (client_ip && ip_is_admin(client_ip)) {
    TSDebug("ats_proxy_filter", "ADMIN bypass from %s", client_ip);
    TSError("[ats_proxy_filter] ADMIN bypass from %s", client_ip);
    TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
    return 0;
  }

  for (int i = 0; i < deny_cnt; i++) {
    if (host_match(host, deny_r[i])) {
      is_denied = 1;
      break;
    }
  }

  if (is_denied) {
    TSDebug("ats_proxy_filter", "DENY %s -> 403", host);
    TSError("[ats_proxy_filter] DENY %s -> 403", host);
    TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);

    TSHttpTxnHookAdd(txnp, TS_HTTP_SEND_RESPONSE_HDR_HOOK,
      TSContCreate((TSEventFunc)handle_response, NULL));
    TSUserArgSet(txnp, arg_idx, (void *)(long)403);
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_ERROR);
    return 0;
  }

  for (int j = 0; j < white_cnt; j++) {
    if (host_match(host, white_r[j])) {
      is_whitelisted = 1;
      break;
    }
  }

  if (is_whitelisted) {
    TSError("[ats_proxy_filter] WHITELIST %s -> pass", host);
    TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
    return 0;
  }

  const char *auth_hdr = NULL;
  int auth_len = 0;
  if (TSMimeHdrFieldFind(bufp, hdr_loc, TS_MIME_FIELD_PROXY_AUTHORIZATION,
        TS_MIME_LEN_PROXY_AUTHORIZATION, &host_field_loc) == TS_SUCCESS) {
    int vlen = 0;
    auth_hdr = TSMimeHdrFieldValueStringGet(bufp, hdr_loc, host_field_loc, -1, &vlen);
    if (auth_hdr && vlen > 0 && vlen < 4096) {
      auth_len = vlen;
    } else {
      auth_hdr = NULL;
    }
  }

  if (auth_hdr && auth_len > 6 && !strncmp(auth_hdr, "Basic ", 6)) {
    const char *b64 = auth_hdr + 6;
    int b64len = auth_len - 6;
    char decoded[256];
    if (b64_decode(b64, b64len, decoded, sizeof(decoded))) {
      char *colon = strchr(decoded, ':');
      if (colon) {
        *colon = '\0';
        if (authorized(decoded, colon + 1)) {
          TSDebug("ats_proxy_filter", "AUTH OK %s", decoded);
          if (host_field_loc)
            TSHandleMLocRelease(bufp, hdr_loc, host_field_loc);
          TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
          TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
          return 0;
        }
        TSError("[ats_proxy_filter] AUTH FAIL %s from %s", decoded, client_ip ? client_ip : "?");
      }
    }
  }

  if (host_field_loc)
    TSHandleMLocRelease(bufp, hdr_loc, host_field_loc);
  TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);

  TSHttpTxnHookAdd(txnp, TS_HTTP_SEND_RESPONSE_HDR_HOOK,
    TSContCreate((TSEventFunc)handle_response, NULL));
  TSUserArgSet(txnp, arg_idx, (void *)(long)TS_HTTP_STATUS_PROXY_AUTHENTICATION_REQUIRED);
  TSHttpTxnReenable(txnp, TS_EVENT_HTTP_ERROR);
  return 0;
}

static void load_cfg(void) {
  FILE *f = fopen(CFG_PATH, "r");
  if (!f) {
    TSError("[ats_proxy_filter] cannot open config: %s", CFG_PATH);
    return;
  }
  char line[MAX_LINE];
  while (fgets(line, sizeof(line), f)) {
    while (line[0] && line[strlen(line)-1] == '\n') line[strlen(line)-1] = '\0';
    if (line[0] == '#' || line[0] == '\0') continue;

    char cmd[32], v1[256], v2[64];
    v1[0] = v2[0] = '\0';
    int n = sscanf(line, "%31s %255s %63s", cmd, v1, v2);

    if (n >= 2 && !strcmp(cmd, "ADMIN") && admin_cnt < MAX_ADMIN) {
      strncpy(admin_ips[admin_cnt], v1, sizeof(admin_ips[admin_cnt])-1);
      admin_ips[admin_cnt][sizeof(admin_ips[admin_cnt])-1] = '\0';
      admin_cnt++;
    } else if (n >= 2 && !strcmp(cmd, "DENY") && deny_cnt < MAX_DENY) {
      strncpy(deny_r[deny_cnt], v1, sizeof(deny_r[deny_cnt])-1);
      deny_r[deny_cnt][sizeof(deny_r[deny_cnt])-1] = '\0';
      deny_cnt++;
    } else if (n >= 2 && !strcmp(cmd, "WHITELIST") && white_cnt < MAX_WHITE) {
      strncpy(white_r[white_cnt], v1, sizeof(white_r[white_cnt])-1);
      white_r[white_cnt][sizeof(white_r[white_cnt])-1] = '\0';
      white_cnt++;
    } else if (n == 3 && !strcmp(cmd, "USER") && users_cnt < MAX_USERS) {
      strncpy(users[users_cnt], v1, sizeof(users[users_cnt])-1);
      users[users_cnt][sizeof(users[users_cnt])-1] = '\0';
      strncpy(passes[users_cnt], v2, sizeof(passes[users_cnt])-1);
      passes[users_cnt][sizeof(passes[users_cnt])-1] = '\0';
      users_cnt++;
    }
  }
  fclose(f);
  TSError("[ats_proxy_filter] loaded config: %d admin, %d deny, %d whitelist, %d users",
    admin_cnt, deny_cnt, white_cnt, users_cnt);
}

static int auth_plugin(TSCont contp, TSEvent event, void *edata) {
  if (event == TS_EVENT_HTTP_OS_DNS) {
    return handle_dns(contp, event, edata);
  } else if (event == TS_EVENT_HTTP_SEND_RESPONSE_HDR) {
    handle_response(contp, event, edata);
    return 0;
  }
  TSHttpTxnReenable((TSHttpTxn)edata, TS_EVENT_HTTP_CONTINUE);
  return 0;
}

void TSPluginInit(int argc, const char *argv[]) {
  TSPluginRegistrationInfo info;
  info.plugin_name = "ats_proxy_filter";
  info.vendor_name  = "ATS Proxy Enterprise";
  info.support_email = "proxy@tripersonale.org";

  if (TSPluginRegister(&info) != TS_SUCCESS) {
    TSError("[ats_proxy_filter] plugin registration failed");
    return;
  }

  arg_idx = TSHttpTxnArgReserve("ats_proxy_filter", "filter action");
  if (arg_idx < 0) {
    TSError("[ats_proxy_filter] cannot reserve TXN arg");
    return;
  }

  load_cfg();

  TSCont contp = TSContCreate(auth_plugin, NULL);
  TSHttpHookAdd(TS_HTTP_OS_DNS_HOOK, contp);

  TSError("[ats_proxy_filter] plugin loaded, arg_idx=%d", arg_idx);
}

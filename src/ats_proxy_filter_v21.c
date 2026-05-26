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
  int i, j;
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
      if (j == 0)      v = (unsigned char)((d[0] << 2) | (d[1] >> 4));
      else if (j == 1) v = (unsigned char)(((d[1] & 0x0F) << 4) | (d[2] >> 2));
      else             v = (unsigned char)(((d[2] & 0x03) << 6) | d[3]);
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

static void handle_response(TSCont contp, TSEvent event, void *edata) {
  TSHttpTxn txnp = (TSHttpTxn)edata;
  TSMBuffer bufp;
  TSMLoc hdr_loc;

  if (TSHttpTxnClientRespGet(txnp, &bufp, &hdr_loc) != TS_SUCCESS) return;

  int status = 200;
  void *arg = TSUserArgGet(txnp, arg_idx);
  if (arg) status = (int)(long)arg;

  TSHttpHdrStatusSet(bufp, hdr_loc, (TSHttpStatus)status);

  if (status == 403) {
    TSHttpHdrReasonSet(bufp, hdr_loc, "Forbidden", -1);
  } else if (status == 407 || status == TS_HTTP_STATUS_PROXY_AUTHENTICATION_REQUIRED) {
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
}

static int handle_dns(TSCont contp, TSEvent event, void *edata) {
  TSHttpTxn txnp = (TSHttpTxn)edata;
  TSMBuffer bufp;
  TSMLoc hdr_loc, field_loc;
  const char *host;
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

  char host_copy[256];
  int copy_len = vlen < (int)sizeof(host_copy) - 1 ? vlen : (int)sizeof(host_copy) - 1;
  memcpy(host_copy, host, copy_len);
  host_copy[copy_len] = '\0';

  TSHandleMLocRelease(bufp, hdr_loc, field_loc);

  struct sockaddr const *client_addr = TSHttpTxnClientAddrGet(txnp);
  char client_ip[64] = "?";
  if (client_addr) {
    if (client_addr->sa_family == AF_INET) {
      struct sockaddr_in *sin = (struct sockaddr_in *)client_addr;
      snprintf(client_ip, sizeof(client_ip), "%d.%d.%d.%d",
        (ntohl(sin->sin_addr.s_addr) >> 24) & 0xFF,
        (ntohl(sin->sin_addr.s_addr) >> 16) & 0xFF,
        (ntohl(sin->sin_addr.s_addr) >> 8) & 0xFF,
        ntohl(sin->sin_addr.s_addr) & 0xFF);
    } else if (client_addr->sa_family == AF_INET6) {
      snprintf(client_ip, sizeof(client_ip), "IPv6");
    }
  }

  if (ip_is_admin(client_ip)) {
    TSError("[ats_proxy_filter] ADMIN bypass from %s host=%s", client_ip, host_copy);
    TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
    return 0;
  }

  for (int i = 0; i < deny_cnt; i++) {
    if (host_match(host_copy, deny_r[i])) {
      is_denied = 1;
      break;
    }
  }

  if (is_denied) {
    TSError("[ats_proxy_filter] DENY %s -> 403", host_copy);
    TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);

    TSHttpTxnHookAdd(txnp, TS_HTTP_SEND_RESPONSE_HDR_HOOK,
      TSContCreate((TSEventFunc)handle_response, NULL));
    TSUserArgSet(txnp, arg_idx, (void *)(long)TS_HTTP_STATUS_FORBIDDEN);
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_ERROR);
    return 0;
  }

  for (int j = 0; j < white_cnt; j++) {
    if (host_match(host_copy, white_r[j])) {
      is_whitelisted = 1;
      break;
    }
  }

  if (is_whitelisted) {
    TSError("[ats_proxy_filter] WHITELIST %s -> pass", host_copy);
    TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
    TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
    return 0;
  }

  const char *auth_hdr = NULL;
  TSMLoc auth_field_loc = TSMimeHdrFieldFind(bufp, hdr_loc,
    TS_MIME_FIELD_PROXY_AUTHORIZATION, TS_MIME_LEN_PROXY_AUTHORIZATION);
  if (auth_field_loc != TS_NULL_MLOC) {
    int avlen = 0;
    auth_hdr = TSMimeHdrFieldValueStringGet(bufp, hdr_loc, auth_field_loc, -1, &avlen);
    if (auth_hdr && avlen > 6 && !strncmp(auth_hdr, "Basic ", 6)) {
      char decoded[256];
      if (b64_decode(auth_hdr + 6, avlen - 6, decoded, sizeof(decoded))) {
        char *colon = strchr(decoded, ':');
        if (colon) {
          *colon = '\0';
          if (authorized(decoded, colon + 1)) {
            TSError("[ats_proxy_filter] AUTH OK %s host=%s", decoded, host_copy);
            TSHandleMLocRelease(bufp, hdr_loc, auth_field_loc);
            TSHandleMLocRelease(bufp, TS_NULL_MLOC, hdr_loc);
            TSHttpTxnReenable(txnp, TS_EVENT_HTTP_CONTINUE);
            return 0;
          }
          TSError("[ats_proxy_filter] AUTH FAIL %s from %s", decoded, client_ip);
        }
      }
    }
    TSHandleMLocRelease(bufp, hdr_loc, auth_field_loc);
  }

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

  TSUserArgIndexReserve(TS_USER_ARGS_TXN, "ats_proxy_filter", "filter action", &arg_idx);

  load_cfg();

  TSCont contp = TSContCreate(auth_plugin, NULL);
  TSHttpHookAdd(TS_HTTP_OS_DNS_HOOK, contp);

  TSError("[ats_proxy_filter] plugin loaded, arg_idx=%d", arg_idx);
}

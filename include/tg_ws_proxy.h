#ifndef TG_WS_PROXY_H
#define TG_WS_PROXY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int StartProxy(const char* host, int port, const char* dcIps, const char* secret, int verbose);
int StopProxy(void);
void SetPoolSize(int size);
void SetCfProxyCacheDir(const char* cacheDir);
void SetCfProxyConfig(int enabled, const char* userDomain);
void SetRouteMode(int mode);
void SetProxyProtocol(int enabled);
void SetCfWorkerConfig(int enabled, const char* workerURL);
void SetSecret(const char* secret);
void SetFakeTls(int enabled, const char* domain, const char* maskHost);
void SetFragmentConfig(int enabled, int firstSize, int delayMs);
void SetTlsFingerprint(int fp);
void SetFakeSni(int enabled, const char* value);
void SetDohConfig(int useCloudflare, int useGoogle, int useQuad9, int useAdguard, const char* customURL);
char* GetSecretWithPrefix(void);
char* GetStats(void);
char* GetLogs(void);
void FreeString(char* p);

#ifdef __cplusplus
}
#endif

#endif /* TG_WS_PROXY_H */

#ifndef MOONECAT_NPCAP_COMPAT_H
#define MOONECAT_NPCAP_COMPAT_H

#ifdef _WIN32

#ifndef __cdecl
#define __cdecl
#endif

typedef unsigned int bpf_u_int32;
typedef unsigned char u_char;

typedef struct pcap pcap_t;
typedef struct pcap_addr pcap_addr_t;
struct pcap_rmtauth;

typedef struct pcap_if {
  struct pcap_if *next;
  char *name;
  char *description;
  pcap_addr_t *addresses;
  bpf_u_int32 flags;
} pcap_if_t;

struct moonecat_pcap_timeval {
  long tv_sec;
  long tv_usec;
};

struct pcap_pkthdr {
  struct moonecat_pcap_timeval ts;
  bpf_u_int32 caplen;
  bpf_u_int32 len;
};

#define PCAP_ERRBUF_SIZE 256
#define PCAP_CHAR_ENC_LOCAL 0

#define PCAP_IF_LOOPBACK 0x00000001U
#define PCAP_IF_WIRELESS 0x00000008U
#define PCAP_IF_CONNECTION_STATUS 0x00000030U
#define PCAP_IF_CONNECTION_STATUS_UNKNOWN 0x00000000U
#define PCAP_IF_CONNECTION_STATUS_CONNECTED 0x00000010U
#define PCAP_IF_CONNECTION_STATUS_DISCONNECTED 0x00000020U
#define PCAP_IF_CONNECTION_STATUS_NOT_APPLICABLE 0x00000030U

#define PCAP_OPENFLAG_PROMISCUOUS 0x00000001
#define PCAP_OPENFLAG_NOCAPTURE_LOCAL 0x00000008
#define PCAP_OPENFLAG_MAX_RESPONSIVENESS 0x00000010

#define DLT_EN10MB 1

typedef int(__cdecl *moonecat_pcap_init_fn)(unsigned int, char *);
typedef int(__cdecl *moonecat_pcap_findalldevs_fn)(pcap_if_t **, char *);
typedef void(__cdecl *moonecat_pcap_freealldevs_fn)(pcap_if_t *);
typedef pcap_t *(__cdecl *moonecat_pcap_open_fn)(const char *, int, int, int,
                                                 struct pcap_rmtauth *, char *);
typedef pcap_t *(__cdecl *moonecat_pcap_open_live_fn)(const char *, int, int,
                                                      int, char *);
typedef int(__cdecl *moonecat_pcap_datalink_fn)(pcap_t *);
typedef void(__cdecl *moonecat_pcap_close_fn)(pcap_t *);
typedef int(__cdecl *moonecat_pcap_sendpacket_fn)(pcap_t *, const u_char *,
                                                  int);
typedef moonecat_pcap_sendpacket_fn moonecat_pcap_sendpacket_fn_t;
typedef int(__cdecl *moonecat_pcap_next_ex_fn)(pcap_t *, struct pcap_pkthdr **,
                                               const u_char **);
typedef moonecat_pcap_next_ex_fn moonecat_pcap_next_ex_fn_t;
typedef char *(__cdecl *moonecat_pcap_geterr_fn)(pcap_t *);

extern pcap_t *g_npcap_handles[32];
extern moonecat_pcap_sendpacket_fn g_pcap_sendpacket;
extern moonecat_pcap_next_ex_fn g_pcap_next_ex;

#endif

#endif

#include <stdint.h>
#include <string.h>

#include <moonbit.h>

static int32_t g_last_error_code = 1;
static char g_last_error_message[512] = "ok";

static void moonecat_set_error(int32_t code, const char *message) {
  g_last_error_code = code;
  if (message == NULL) {
    g_last_error_message[0] = '\0';
    return;
  }
  strncpy(g_last_error_message, message, sizeof(g_last_error_message) - 1);
  g_last_error_message[sizeof(g_last_error_message) - 1] = '\0';
}

MOONBIT_FFI_EXPORT
int32_t moonecat_native_stub_version(void) { return 1; }

MOONBIT_FFI_EXPORT
int32_t moonecat_native_last_error_code(void) { return g_last_error_code; }

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonecat_native_last_error_message(void) {
  int32_t len = (int32_t)strlen(g_last_error_message);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, g_last_error_message, len);
  return bytes;
}

static size_t moonecat_append_text(char *buffer, size_t capacity, size_t used,
                                   const char *text) {
  size_t remaining;
  size_t len;
  if (used >= capacity) {
    return used;
  }
  if (text == NULL) {
    text = "";
  }
  remaining = capacity - used;
  len = strlen(text);
  if (len >= remaining) {
    len = remaining - 1;
  }
  memcpy(buffer + used, text, len);
  used += len;
  buffer[used] = '\0';
  return used;
}

static size_t moonecat_append_json_string(char *buffer, size_t capacity,
                                          size_t used, const char *text) {
  const unsigned char *cursor =
      (const unsigned char *)(text == NULL ? "" : text);
  used = moonecat_append_text(buffer, capacity, used, "\"");
  while (*cursor != '\0' && used + 2 < capacity) {
    switch (*cursor) {
    case '\\':
      used = moonecat_append_text(buffer, capacity, used, "\\\\");
      break;
    case '"':
      used = moonecat_append_text(buffer, capacity, used, "\\\"");
      break;
    case '\n':
      used = moonecat_append_text(buffer, capacity, used, "\\n");
      break;
    case '\r':
      used = moonecat_append_text(buffer, capacity, used, "\\r");
      break;
    case '\t':
      used = moonecat_append_text(buffer, capacity, used, "\\t");
      break;
    default: {
      char ch[2];
      ch[0] = (char)*cursor;
      ch[1] = '\0';
      used = moonecat_append_text(buffer, capacity, used, ch);
      break;
    }
    }
    cursor++;
  }
  return moonecat_append_text(buffer, capacity, used, "\"");
}

static moonbit_bytes_t moonecat_bytes_from_buffer(const char *buffer,
                                                  size_t used) {
  moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)used, 0);
  memcpy(bytes, buffer, used);
  return bytes;
}

#ifdef _WIN32

#define WIN32_LEAN_AND_MEAN
#include <pcap.h>
#include <tchar.h>
#include <windows.h>


typedef int(__cdecl *moonecat_pcap_init_fn)(unsigned int, char *);
typedef int(__cdecl *moonecat_pcap_findalldevs_fn)(pcap_if_t **, char *);
typedef void(__cdecl *moonecat_pcap_freealldevs_fn)(pcap_if_t *);
typedef pcap_t *(__cdecl *moonecat_pcap_open_fn)(const char *, int, int, int,
                                                 struct pcap_rmtauth *, char *);
typedef pcap_t *(__cdecl *moonecat_pcap_open_live_fn)(const char *, int, int,
                                                      int, char *);
typedef int(__cdecl *moonecat_pcap_datalink_fn)(pcap_t *);
typedef int(__cdecl *moonecat_pcap_setdirection_fn)(pcap_t *, pcap_direction_t);
typedef void(__cdecl *moonecat_pcap_close_fn)(pcap_t *);
typedef int(__cdecl *moonecat_pcap_sendpacket_fn)(pcap_t *, const u_char *,
                                                  int);
typedef int(__cdecl *moonecat_pcap_next_ex_fn)(pcap_t *, struct pcap_pkthdr **,
                                               const u_char **);
typedef char *(__cdecl *moonecat_pcap_geterr_fn)(pcap_t *);

static pcap_t *g_npcap_handles[32] = {0};
static int g_npcap_initialized = 0;
static HMODULE g_npcap_module = NULL;
static moonecat_pcap_init_fn g_pcap_init = NULL;
static moonecat_pcap_findalldevs_fn g_pcap_findalldevs = NULL;
static moonecat_pcap_freealldevs_fn g_pcap_freealldevs = NULL;
static moonecat_pcap_open_fn g_pcap_open = NULL;
static moonecat_pcap_open_live_fn g_pcap_open_live = NULL;
static moonecat_pcap_datalink_fn g_pcap_datalink = NULL;
static moonecat_pcap_setdirection_fn g_pcap_setdirection = NULL;
static moonecat_pcap_close_fn g_pcap_close = NULL;
static moonecat_pcap_sendpacket_fn g_pcap_sendpacket = NULL;
static moonecat_pcap_next_ex_fn g_pcap_next_ex = NULL;
static moonecat_pcap_geterr_fn g_pcap_geterr = NULL;

static int moonecat_find_free_handle_slot(void) {
  int i;
  for (i = 0; i < 32; i++) {
    if (g_npcap_handles[i] == NULL) {
      return i;
    }
  }
  return -1;
}

static int moonecat_load_npcap_dlls(void) {
  _TCHAR npcap_dir[512];
  UINT len = GetSystemDirectory(npcap_dir, 480);
  if (!len) {
    moonecat_set_error(-1, "GetSystemDirectory failed while loading Npcap");
    return 0;
  }
  _tcscat_s(npcap_dir, 512, _T("\\Npcap"));
  if (SetDllDirectory(npcap_dir) == 0) {
    moonecat_set_error(-1, "SetDllDirectory failed while loading Npcap");
    return 0;
  }
  return 1;
}

static int moonecat_load_npcap_symbols(void) {
  if (g_npcap_module != NULL) {
    return 1;
  }
  g_npcap_module = LoadLibrary(TEXT("wpcap.dll"));
  if (g_npcap_module == NULL) {
    moonecat_set_error(-1, "LoadLibrary(wpcap.dll) failed while loading Npcap");
    return 0;
  }
  g_pcap_init =
      (moonecat_pcap_init_fn)GetProcAddress(g_npcap_module, "pcap_init");
  g_pcap_findalldevs = (moonecat_pcap_findalldevs_fn)GetProcAddress(
      g_npcap_module, "pcap_findalldevs");
  g_pcap_freealldevs = (moonecat_pcap_freealldevs_fn)GetProcAddress(
      g_npcap_module, "pcap_freealldevs");
  g_pcap_open =
      (moonecat_pcap_open_fn)GetProcAddress(g_npcap_module, "pcap_open");
  g_pcap_open_live = (moonecat_pcap_open_live_fn)GetProcAddress(
      g_npcap_module, "pcap_open_live");
  g_pcap_datalink = (moonecat_pcap_datalink_fn)GetProcAddress(g_npcap_module,
                                                              "pcap_datalink");
  g_pcap_setdirection = (moonecat_pcap_setdirection_fn)GetProcAddress(
      g_npcap_module, "pcap_setdirection");
  g_pcap_close =
      (moonecat_pcap_close_fn)GetProcAddress(g_npcap_module, "pcap_close");
  g_pcap_sendpacket = (moonecat_pcap_sendpacket_fn)GetProcAddress(
      g_npcap_module, "pcap_sendpacket");
  g_pcap_next_ex =
      (moonecat_pcap_next_ex_fn)GetProcAddress(g_npcap_module, "pcap_next_ex");
  g_pcap_geterr =
      (moonecat_pcap_geterr_fn)GetProcAddress(g_npcap_module, "pcap_geterr");
  if (g_pcap_init == NULL || g_pcap_findalldevs == NULL ||
      g_pcap_freealldevs == NULL ||
      (g_pcap_open == NULL && g_pcap_open_live == NULL) ||
      g_pcap_datalink == NULL || g_pcap_close == NULL ||
      g_pcap_sendpacket == NULL || g_pcap_next_ex == NULL ||
      g_pcap_geterr == NULL) {
    moonecat_set_error(-1, "GetProcAddress failed for required Npcap symbol");
    return 0;
  }
  return 1;
}

static int moonecat_ensure_npcap_initialized(void) {
  char errbuf[PCAP_ERRBUF_SIZE + 1] = {0};
  if (g_npcap_initialized) {
    return 1;
  }
  if (!moonecat_load_npcap_dlls()) {
    return 0;
  }
  if (!moonecat_load_npcap_symbols()) {
    return 0;
  }
  if (g_pcap_init(PCAP_CHAR_ENC_LOCAL, errbuf) != 0) {
    moonecat_set_error(-1, errbuf[0] ? errbuf : "pcap_init failed");
    return 0;
  }
  g_npcap_initialized = 1;
  moonecat_set_error(1, "ok");
  return 1;
}

MOONBIT_FFI_EXPORT
int32_t moonecat_windows_npcap_available(void) {
  return moonecat_ensure_npcap_initialized();
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonecat_windows_npcap_list_interfaces_text(void) {
  pcap_if_t *alldevs = NULL;
  pcap_if_t *dev;
  char errbuf[PCAP_ERRBUF_SIZE + 1] = {0};
  char listing[8192] = {0};
  size_t used = 0;
  moonbit_bytes_t bytes;
  if (!moonecat_ensure_npcap_initialized()) {
    return moonbit_make_bytes(0, 0);
  }
  if (g_pcap_findalldevs(&alldevs, errbuf) != 0) {
    moonecat_set_error(-1, errbuf[0] ? errbuf : "pcap_findalldevs failed");
    return moonbit_make_bytes(0, 0);
  }
  for (dev = alldevs; dev != NULL; dev = dev->next) {
    used = moonecat_append_text(listing, sizeof(listing), used, dev->name);
    used = moonecat_append_text(listing, sizeof(listing), used, "\t");
    used =
        moonecat_append_text(listing, sizeof(listing), used, dev->description);
    used = moonecat_append_text(listing, sizeof(listing), used, "\n");
    if (used + 1 >= sizeof(listing)) {
      break;
    }
  }
  g_pcap_freealldevs(alldevs);
  moonecat_set_error(1, "ok");
  bytes = moonbit_make_bytes((int32_t)used, 0);
  memcpy(bytes, listing, used);
  return bytes;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonecat_windows_npcap_list_interfaces_json(void) {
  pcap_if_t *alldevs = NULL;
  pcap_if_t *dev;
  char errbuf[PCAP_ERRBUF_SIZE + 1] = {0};
  char listing[16384] = {0};
  size_t used = 0;
  int first = 1;
  if (!moonecat_ensure_npcap_initialized()) {
    return moonbit_make_bytes(0, 0);
  }
  if (g_pcap_findalldevs(&alldevs, errbuf) != 0) {
    moonecat_set_error(-1, errbuf[0] ? errbuf : "pcap_findalldevs failed");
    return moonbit_make_bytes(0, 0);
  }
  used = moonecat_append_text(
      listing, sizeof(listing), used,
      "{\"backend\":\"native-windows-npcap\",\"interfaces\":[");
  for (dev = alldevs; dev != NULL; dev = dev->next) {
    if (!first) {
      used = moonecat_append_text(listing, sizeof(listing), used, ",");
    }
    first = 0;
    used = moonecat_append_text(listing, sizeof(listing), used, "{\"name\":");
    used =
        moonecat_append_json_string(listing, sizeof(listing), used, dev->name);
    used = moonecat_append_text(listing, sizeof(listing), used,
                                ",\"description\":");
    used = moonecat_append_json_string(listing, sizeof(listing), used,
                                       dev->description);
    used =
        moonecat_append_text(listing, sizeof(listing), used, ",\"loopback\":");
    used = moonecat_append_text(listing, sizeof(listing), used,
                                (dev->flags & PCAP_IF_LOOPBACK) ? "true"
                                                                : "false");
    used = moonecat_append_text(listing, sizeof(listing), used, "}");
    if (used + 64 >= sizeof(listing)) {
      break;
    }
  }
  g_pcap_freealldevs(alldevs);
  used = moonecat_append_text(listing, sizeof(listing), used, "]}");
  moonecat_set_error(1, "ok");
  return moonecat_bytes_from_buffer(listing, used);
}

MOONBIT_FFI_EXPORT
int32_t moonecat_windows_npcap_open(const char *name, int32_t snaplen,
                                    int32_t promisc, int32_t timeout_ms) {
  char errbuf[PCAP_ERRBUF_SIZE + 1] = {0};
  pcap_t *handle;
  int slot;
  if (!moonecat_ensure_npcap_initialized()) {
    return -1;
  }
  if (g_pcap_open != NULL) {
    int flags =
        PCAP_OPENFLAG_MAX_RESPONSIVENESS | PCAP_OPENFLAG_NOCAPTURE_LOCAL;
    if (promisc) {
      flags |= PCAP_OPENFLAG_PROMISCUOUS;
    }
    handle = g_pcap_open(name, snaplen, flags, timeout_ms, NULL, errbuf);
  } else {
    handle =
        g_pcap_open_live(name, snaplen, promisc ? 1 : 0, timeout_ms, errbuf);
  }
  if (handle == NULL) {
    moonecat_set_error(-1, errbuf[0] ? errbuf : "pcap_open_live failed");
    return -1;
  }
  if (g_pcap_datalink(handle) != DLT_EN10MB) {
    g_pcap_close(handle);
    moonecat_set_error(-1, "Npcap adapter is not DLT_EN10MB");
    return -1;
  }
  slot = moonecat_find_free_handle_slot();
  if (slot < 0) {
    g_pcap_close(handle);
    moonecat_set_error(-1, "No free Npcap handle slot");
    return -1;
  }
  g_npcap_handles[slot] = handle;
  moonecat_set_error(1, "ok");
  return slot + 1;
}

MOONBIT_FFI_EXPORT
int32_t moonecat_windows_npcap_send(int32_t handle_id, moonbit_bytes_t data,
                                    int32_t length) {
  pcap_t *handle;
  int rc;
  if (handle_id <= 0 || handle_id > 32) {
    moonecat_set_error(-1, "Invalid Npcap handle id");
    return -1;
  }
  handle = g_npcap_handles[handle_id - 1];
  if (handle == NULL) {
    moonecat_set_error(-1, "Npcap handle is closed");
    return -1;
  }
  rc = g_pcap_sendpacket(handle, (const u_char *)data, length);
  if (rc != 0) {
    moonecat_set_error(-1, g_pcap_geterr(handle));
    return -1;
  }
  moonecat_set_error(1, "ok");
  return length;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonecat_windows_npcap_recv(int32_t handle_id) {
  struct pcap_pkthdr *header = NULL;
  const u_char *packet = NULL;
  pcap_t *handle;
  int rc;
  moonbit_bytes_t bytes;
  if (handle_id <= 0 || handle_id > 32) {
    moonecat_set_error(-1, "Invalid Npcap handle id");
    return moonbit_make_bytes(0, 0);
  }
  handle = g_npcap_handles[handle_id - 1];
  if (handle == NULL) {
    moonecat_set_error(-1, "Npcap handle is closed");
    return moonbit_make_bytes(0, 0);
  }
  rc = g_pcap_next_ex(handle, &header, &packet);
  if (rc == 1) {
    bytes = moonbit_make_bytes((int32_t)header->caplen, 0);
    memcpy(bytes, packet, header->caplen);
    moonecat_set_error(1, "ok");
    return bytes;
  }
  if (rc == 0) {
    moonecat_set_error(0, "recv timeout");
    return moonbit_make_bytes(0, 0);
  }
  moonecat_set_error(-1, g_pcap_geterr(handle));
  return moonbit_make_bytes(0, 0);
}

MOONBIT_FFI_EXPORT
void moonecat_windows_npcap_close(int32_t handle_id) {
  if (handle_id <= 0 || handle_id > 32) {
    return;
  }
  if (g_npcap_handles[handle_id - 1] != NULL) {
    g_pcap_close(g_npcap_handles[handle_id - 1]);
    g_npcap_handles[handle_id - 1] = NULL;
  }
  moonecat_set_error(1, "ok");
}

#else

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonecat_windows_npcap_list_interfaces_json(void) {
  moonecat_set_error(-1, "Npcap backend is only available on Windows");
  return moonbit_make_bytes(0, 0);
}

MOONBIT_FFI_EXPORT
int32_t moonecat_windows_npcap_available(void) {
  moonecat_set_error(-1, "Npcap backend is only available on Windows");
  return 0;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonecat_windows_npcap_list_interfaces_text(void) {
  moonecat_set_error(-1, "Npcap backend is only available on Windows");
  return moonbit_make_bytes(0, 0);
}

MOONBIT_FFI_EXPORT
int32_t moonecat_windows_npcap_open(const char *name, int32_t snaplen,
                                    int32_t promisc, int32_t timeout_ms) {
  (void)name;
  (void)snaplen;
  (void)promisc;
  (void)timeout_ms;
  moonecat_set_error(-1, "Npcap backend is only available on Windows");
  return -1;
}

MOONBIT_FFI_EXPORT
int32_t moonecat_windows_npcap_send(int32_t handle_id, moonbit_bytes_t data,
                                    int32_t length) {
  (void)handle_id;
  (void)data;
  (void)length;
  moonecat_set_error(-1, "Npcap backend is only available on Windows");
  return -1;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonecat_windows_npcap_recv(int32_t handle_id) {
  (void)handle_id;
  moonecat_set_error(-1, "Npcap backend is only available on Windows");
  return moonbit_make_bytes(0, 0);
}

MOONBIT_FFI_EXPORT
void moonecat_windows_npcap_close(int32_t handle_id) {
  (void)handle_id;
  moonecat_set_error(-1, "Npcap backend is only available on Windows");
}

#endif

#ifdef __linux__

#include <errno.h>
#include <linux/if_ether.h>
#include <linux/if_packet.h>
#include <net/if.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static int g_linux_raw_handles[32] = {0};

static int moonecat_linux_find_free_handle_slot(void) {
  int i;
  for (i = 0; i < 32; i++) {
    if (g_linux_raw_handles[i] == 0) {
      return i;
    }
  }
  return -1;
}

MOONBIT_FFI_EXPORT
int32_t moonecat_linux_raw_socket_available(void) {
  moonecat_set_error(1, "ok");
  return 1;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonecat_linux_raw_socket_list_interfaces_text(void) {
  struct if_nameindex *interfaces = if_nameindex();
  struct if_nameindex *cursor;
  char listing[8192] = {0};
  size_t used = 0;
  if (interfaces == NULL) {
    moonecat_set_error(-1, strerror(errno));
    return moonbit_make_bytes(0, 0);
  }
  for (cursor = interfaces; cursor->if_index != 0 || cursor->if_name != NULL;
       cursor++) {
    used =
        moonecat_append_text(listing, sizeof(listing), used, cursor->if_name);
    used = moonecat_append_text(listing, sizeof(listing), used, "\tindex=");
    {
      char index_text[32];
      _snprintf(index_text, sizeof(index_text), "%u", cursor->if_index);
      used = moonecat_append_text(listing, sizeof(listing), used, index_text);
    }
    used = moonecat_append_text(listing, sizeof(listing), used, "\n");
    if (used + 32 >= sizeof(listing)) {
      break;
    }
  }
  if_freenameindex(interfaces);
  moonecat_set_error(1, "ok");
  return moonecat_bytes_from_buffer(listing, used);
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonecat_linux_raw_socket_list_interfaces_json(void) {
  struct if_nameindex *interfaces = if_nameindex();
  struct if_nameindex *cursor;
  char listing[16384] = {0};
  size_t used = 0;
  int first = 1;
  if (interfaces == NULL) {
    moonecat_set_error(-1, strerror(errno));
    return moonbit_make_bytes(0, 0);
  }
  used = moonecat_append_text(
      listing, sizeof(listing), used,
      "{\"backend\":\"native-linux-raw\",\"interfaces\":[");
  for (cursor = interfaces; cursor->if_index != 0 || cursor->if_name != NULL;
       cursor++) {
    char index_text[32];
    if (!first) {
      used = moonecat_append_text(listing, sizeof(listing), used, ",");
    }
    first = 0;
    _snprintf(index_text, sizeof(index_text), "%u", cursor->if_index);
    used = moonecat_append_text(listing, sizeof(listing), used, "{\"name\":");
    used = moonecat_append_json_string(listing, sizeof(listing), used,
                                       cursor->if_name);
    used = moonecat_append_text(
        listing, sizeof(listing), used,
        ",\"description\":\"linux raw socket\",\"index\":");
    used = moonecat_append_text(listing, sizeof(listing), used, index_text);
    used = moonecat_append_text(listing, sizeof(listing), used, "}");
    if (used + 64 >= sizeof(listing)) {
      break;
    }
  }
  if_freenameindex(interfaces);
  used = moonecat_append_text(listing, sizeof(listing), used, "]}");
  moonecat_set_error(1, "ok");
  return moonecat_bytes_from_buffer(listing, used);
}

MOONBIT_FFI_EXPORT
int32_t moonecat_linux_raw_socket_open(const char *name, int32_t snaplen,
                                       int32_t promisc, int32_t timeout_ms) {
  int fd;
  int slot;
  unsigned int ifindex;
  struct sockaddr_ll addr;
  struct timeval tv;
  (void)snaplen;
  ifindex = if_nametoindex(name);
  if (ifindex == 0) {
    moonecat_set_error(-1, "Linux interface not found");
    return -1;
  }
  fd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
  if (fd < 0) {
    moonecat_set_error(-1, strerror(errno));
    return -1;
  }
  tv.tv_sec = timeout_ms / 1000;
  tv.tv_usec = (timeout_ms % 1000) * 1000;
  if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) != 0) {
    close(fd);
    moonecat_set_error(-1, strerror(errno));
    return -1;
  }
  memset(&addr, 0, sizeof(addr));
  addr.sll_family = AF_PACKET;
  addr.sll_protocol = htons(ETH_P_ALL);
  addr.sll_ifindex = (int)ifindex;
  if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
    close(fd);
    moonecat_set_error(-1, strerror(errno));
    return -1;
  }
  if (promisc) {
    struct packet_mreq mreq;
    memset(&mreq, 0, sizeof(mreq));
    mreq.mr_ifindex = (int)ifindex;
    mreq.mr_type = PACKET_MR_PROMISC;
    if (setsockopt(fd, SOL_PACKET, PACKET_ADD_MEMBERSHIP, &mreq,
                   sizeof(mreq)) != 0) {
      close(fd);
      moonecat_set_error(-1, strerror(errno));
      return -1;
    }
  }
  slot = moonecat_linux_find_free_handle_slot();
  if (slot < 0) {
    close(fd);
    moonecat_set_error(-1, "No free Linux raw socket handle slot");
    return -1;
  }
  g_linux_raw_handles[slot] = fd;
  moonecat_set_error(1, "ok");
  return slot + 1;
}

MOONBIT_FFI_EXPORT
int32_t moonecat_linux_raw_socket_send(int32_t handle_id, moonbit_bytes_t data,
                                       int32_t length) {
  int fd;
  ssize_t rc;
  if (handle_id <= 0 || handle_id > 32) {
    moonecat_set_error(-1, "Invalid Linux raw socket handle id");
    return -1;
  }
  fd = g_linux_raw_handles[handle_id - 1];
  if (fd <= 0) {
    moonecat_set_error(-1, "Linux raw socket handle is closed");
    return -1;
  }
  rc = send(fd, data, (size_t)length, 0);
  if (rc < 0) {
    moonecat_set_error(-1, strerror(errno));
    return -1;
  }
  moonecat_set_error(1, "ok");
  return (int32_t)rc;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonecat_linux_raw_socket_recv(int32_t handle_id) {
  int fd;
  ssize_t rc;
  unsigned char buffer[65536];
  if (handle_id <= 0 || handle_id > 32) {
    moonecat_set_error(-1, "Invalid Linux raw socket handle id");
    return moonbit_make_bytes(0, 0);
  }
  fd = g_linux_raw_handles[handle_id - 1];
  if (fd <= 0) {
    moonecat_set_error(-1, "Linux raw socket handle is closed");
    return moonbit_make_bytes(0, 0);
  }
  rc = recv(fd, buffer, sizeof(buffer), 0);
  if (rc > 0) {
    moonecat_set_error(1, "ok");
    return moonecat_bytes_from_buffer((const char *)buffer, (size_t)rc);
  }
  if (rc < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
    moonecat_set_error(0, "recv timeout");
    return moonbit_make_bytes(0, 0);
  }
  moonecat_set_error(-1, strerror(errno));
  return moonbit_make_bytes(0, 0);
}

MOONBIT_FFI_EXPORT
void moonecat_linux_raw_socket_close(int32_t handle_id) {
  if (handle_id <= 0 || handle_id > 32) {
    return;
  }
  if (g_linux_raw_handles[handle_id - 1] > 0) {
    close(g_linux_raw_handles[handle_id - 1]);
    g_linux_raw_handles[handle_id - 1] = 0;
  }
  moonecat_set_error(1, "ok");
}

#else

MOONBIT_FFI_EXPORT
int32_t moonecat_linux_raw_socket_available(void) {
  moonecat_set_error(-1, "Linux Raw Socket backend is only available on Linux");
  return 0;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonecat_linux_raw_socket_list_interfaces_text(void) {
  moonecat_set_error(-1, "Linux Raw Socket backend is only available on Linux");
  return moonbit_make_bytes(0, 0);
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonecat_linux_raw_socket_list_interfaces_json(void) {
  moonecat_set_error(-1, "Linux Raw Socket backend is only available on Linux");
  return moonbit_make_bytes(0, 0);
}

MOONBIT_FFI_EXPORT
int32_t moonecat_linux_raw_socket_open(const char *name, int32_t snaplen,
                                       int32_t promisc, int32_t timeout_ms) {
  (void)name;
  (void)snaplen;
  (void)promisc;
  (void)timeout_ms;
  moonecat_set_error(-1, "Linux Raw Socket backend is only available on Linux");
  return -1;
}

MOONBIT_FFI_EXPORT
int32_t moonecat_linux_raw_socket_send(int32_t handle_id, moonbit_bytes_t data,
                                       int32_t length) {
  (void)handle_id;
  (void)data;
  (void)length;
  moonecat_set_error(-1, "Linux Raw Socket backend is only available on Linux");
  return -1;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonecat_linux_raw_socket_recv(int32_t handle_id) {
  (void)handle_id;
  moonecat_set_error(-1, "Linux Raw Socket backend is only available on Linux");
  return moonbit_make_bytes(0, 0);
}

MOONBIT_FFI_EXPORT
void moonecat_linux_raw_socket_close(int32_t handle_id) {
  (void)handle_id;
  moonecat_set_error(-1, "Linux Raw Socket backend is only available on Linux");
}

#endif
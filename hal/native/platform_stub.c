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
int32_t moonecat_native_stub_version(void) {
  return 1;
}

MOONBIT_FFI_EXPORT
int32_t moonecat_native_last_error_code(void) {
  return g_last_error_code;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonecat_native_last_error_message(void) {
  int32_t len = (int32_t)strlen(g_last_error_message);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, g_last_error_message, len);
  return bytes;
}

#ifdef _WIN32

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tchar.h>
#include <pcap.h>

static pcap_t *g_npcap_handles[32] = {0};
static int g_npcap_initialized = 0;

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

static int moonecat_ensure_npcap_initialized(void) {
  char errbuf[PCAP_ERRBUF_SIZE + 1] = {0};
  if (g_npcap_initialized) {
    return 1;
  }
  if (!moonecat_load_npcap_dlls()) {
    return 0;
  }
  if (pcap_init(PCAP_CHAR_ENC_LOCAL, errbuf) != 0) {
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
int32_t moonecat_windows_npcap_open(const char *name, int32_t snaplen, int32_t promisc, int32_t timeout_ms) {
  char errbuf[PCAP_ERRBUF_SIZE + 1] = {0};
  pcap_t *handle;
  int slot;
  if (!moonecat_ensure_npcap_initialized()) {
    return -1;
  }
  handle = pcap_open_live(name, snaplen, promisc ? 1 : 0, timeout_ms, errbuf);
  if (handle == NULL) {
    moonecat_set_error(-1, errbuf[0] ? errbuf : "pcap_open_live failed");
    return -1;
  }
  if (pcap_datalink(handle) != DLT_EN10MB) {
    pcap_close(handle);
    moonecat_set_error(-1, "Npcap adapter is not DLT_EN10MB");
    return -1;
  }
  slot = moonecat_find_free_handle_slot();
  if (slot < 0) {
    pcap_close(handle);
    moonecat_set_error(-1, "No free Npcap handle slot");
    return -1;
  }
  g_npcap_handles[slot] = handle;
  moonecat_set_error(1, "ok");
  return slot + 1;
}

MOONBIT_FFI_EXPORT
int32_t moonecat_windows_npcap_send(int32_t handle_id, moonbit_bytes_t data, int32_t length) {
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
  rc = pcap_sendpacket(handle, (const u_char *)data, length);
  if (rc != 0) {
    moonecat_set_error(-1, pcap_geterr(handle));
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
  rc = pcap_next_ex(handle, &header, &packet);
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
  moonecat_set_error(-1, pcap_geterr(handle));
  return moonbit_make_bytes(0, 0);
}

MOONBIT_FFI_EXPORT
void moonecat_windows_npcap_close(int32_t handle_id) {
  if (handle_id <= 0 || handle_id > 32) {
    return;
  }
  if (g_npcap_handles[handle_id - 1] != NULL) {
    pcap_close(g_npcap_handles[handle_id - 1]);
    g_npcap_handles[handle_id - 1] = NULL;
  }
  moonecat_set_error(1, "ok");
}

#else

MOONBIT_FFI_EXPORT
int32_t moonecat_windows_npcap_available(void) {
  moonecat_set_error(-1, "Npcap backend is only available on Windows");
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonecat_windows_npcap_open(const char *name, int32_t snaplen, int32_t promisc, int32_t timeout_ms) {
  (void)name;
  (void)snaplen;
  (void)promisc;
  (void)timeout_ms;
  moonecat_set_error(-1, "Npcap backend is only available on Windows");
  return -1;
}

MOONBIT_FFI_EXPORT
int32_t moonecat_windows_npcap_send(int32_t handle_id, moonbit_bytes_t data, int32_t length) {
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
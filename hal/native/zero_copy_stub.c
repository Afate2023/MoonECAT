/*
 * MoonECAT Zero-Copy FFI Stubs
 *
 * These functions receive into / send from pre-allocated FixedArray[Byte]
 * buffers, eliminating per-cycle GC heap allocation via moonbit_make_bytes.
 *
 * Key difference from original stubs:
 *   Original: recv → moonbit_make_bytes(len) → memcpy → return new Bytes
 *   Zero-copy: recv → memcpy into caller's FixedArray[Byte] → return length
 */

#include <stdint.h>
#include <string.h>
#include <moonbit.h>

/* ── Windows Npcap zero-copy ──────────────────────────────────── */
#ifdef _WIN32

#include <pcap.h>

/* Shared handle table from platform_stub.c */
extern pcap_t *g_npcap_handles[32];

/* Shared function pointers from platform_stub.c (dynamic wpcap.dll) */
typedef int(__cdecl *moonecat_pcap_sendpacket_fn_t)(pcap_t *,
                                                     const u_char *, int);
typedef int(__cdecl *moonecat_pcap_next_ex_fn_t)(pcap_t *,
                                                  struct pcap_pkthdr **,
                                                  const u_char **);
extern moonecat_pcap_sendpacket_fn_t g_pcap_sendpacket;
extern moonecat_pcap_next_ex_fn_t g_pcap_next_ex;

/*
 * Receive an Ethernet frame directly into a pre-allocated buffer.
 * Returns: >0 = bytes received, 0 = timeout, <0 = error.
 * The buf parameter is a #borrow'd FixedArray[Byte] from MoonBit.
 */
MOONBIT_FFI_EXPORT
int32_t moonecat_npcap_recv_into(int32_t handle_id,
                                  moonbit_bytes_t buf,
                                  int32_t max_len) {
  struct pcap_pkthdr *header = NULL;
  const u_char *packet = NULL;
  pcap_t *handle;
  int rc;
  int32_t copy_len;

  if (handle_id <= 0 || handle_id > 32) return -1;
  handle = g_npcap_handles[handle_id - 1];
  if (handle == NULL) return -1;

  rc = g_pcap_next_ex(handle, &header, &packet);
  if (rc == 1) {
    copy_len = (int32_t)header->caplen;
    if (copy_len > max_len) copy_len = max_len;
    memcpy(buf, packet, copy_len);
    return copy_len;
  }
  if (rc == 0) return 0;  /* timeout */
  return -1;  /* error */
}

/*
 * Send an Ethernet frame from a pre-allocated FixedArray[Byte] buffer.
 * Returns: bytes sent on success, <0 on error.
 */
MOONBIT_FFI_EXPORT
int32_t moonecat_npcap_send_fixed(int32_t handle_id,
                                   moonbit_bytes_t buf,
                                   int32_t length) {
  pcap_t *handle;
  if (handle_id <= 0 || handle_id > 32) return -1;
  handle = g_npcap_handles[handle_id - 1];
  if (handle == NULL) return -1;

  if (g_pcap_sendpacket(handle, (const u_char *)buf, length) != 0) {
    return -1;
  }
  return length;
}

#else  /* Non-Windows stubs */

MOONBIT_FFI_EXPORT
int32_t moonecat_npcap_recv_into(int32_t handle_id,
                                  moonbit_bytes_t buf,
                                  int32_t max_len) {
  (void)handle_id; (void)buf; (void)max_len;
  return -1;
}

MOONBIT_FFI_EXPORT
int32_t moonecat_npcap_send_fixed(int32_t handle_id,
                                   moonbit_bytes_t buf,
                                   int32_t length) {
  (void)handle_id; (void)buf; (void)length;
  return -1;
}

#endif  /* _WIN32 */


/* ── Linux Raw Socket zero-copy ───────────────────────────────── */
#ifdef __linux__

#include <sys/socket.h>
#include <errno.h>

/* Shared handle table from platform_stub.c */
extern int g_linux_raw_handles[32];

/*
 * Receive directly into pre-allocated buffer.
 * True zero-copy from kernel: recv() writes directly to the target buffer.
 * Returns: >0 = bytes received, 0 = timeout (EAGAIN), <0 = error.
 */
MOONBIT_FFI_EXPORT
int32_t moonecat_linux_recv_into(int32_t handle_id,
                                  moonbit_bytes_t buf,
                                  int32_t max_len) {
  int fd;
  ssize_t rc;

  if (handle_id <= 0 || handle_id > 32) return -1;
  fd = g_linux_raw_handles[handle_id - 1];
  if (fd <= 0) return -1;

  rc = recv(fd, buf, (size_t)max_len, 0);
  if (rc > 0) return (int32_t)rc;
  if (rc < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return 0;
  return -1;
}

/*
 * Send from pre-allocated FixedArray[Byte] buffer.
 */
MOONBIT_FFI_EXPORT
int32_t moonecat_linux_send_fixed(int32_t handle_id,
                                   moonbit_bytes_t buf,
                                   int32_t length) {
  int fd;
  ssize_t rc;

  if (handle_id <= 0 || handle_id > 32) return -1;
  fd = g_linux_raw_handles[handle_id - 1];
  if (fd <= 0) return -1;

  rc = send(fd, buf, (size_t)length, 0);
  if (rc > 0) return (int32_t)rc;
  return -1;
}

#else  /* Non-Linux stubs */

#ifndef _WIN32
/* Only provide stubs if neither Windows nor Linux (e.g. macOS cross-compile) */
#endif

MOONBIT_FFI_EXPORT
int32_t moonecat_linux_recv_into(int32_t handle_id,
                                  moonbit_bytes_t buf,
                                  int32_t max_len) {
  (void)handle_id; (void)buf; (void)max_len;
  return -1;
}

MOONBIT_FFI_EXPORT
int32_t moonecat_linux_send_fixed(int32_t handle_id,
                                   moonbit_bytes_t buf,
                                   int32_t length) {
  (void)handle_id; (void)buf; (void)length;
  return -1;
}

#endif  /* __linux__ */

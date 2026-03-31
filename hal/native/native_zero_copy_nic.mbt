///|
/// NativeZeroCopyNic wraps the existing NativeNic handle with a FramePool
/// for zero-allocation send/recv operations on the hot path.
pub(all) struct NativeZeroCopyNic {
  config : NativeNicConfig
  pool : @hal.FramePool
  mut handle_id : Int
  mut is_open : Bool
  mut resolved_backend : NativeBackendKind
}

///|
pub fn NativeZeroCopyNic::new(
  config : NativeNicConfig,
  pool : @hal.FramePool
) -> NativeZeroCopyNic {
  {
    config,
    pool,
    handle_id: 0,
    is_open: false,
    resolved_backend: config.backend,
  }
}

///|
impl @hal.ZeroCopyNic for NativeZeroCopyNic with open_(
  name : String,
  pool : @hal.FramePool
) -> NativeZeroCopyNic raise @hal.EcError {
  let config = default_native_config(name)
  let backend = resolve_native_backend(config.backend)
  let handle_id = match backend {
    WindowsNpcap => windows_npcap_open(config)
    LinuxRawSocket => linux_raw_socket_open(config)
    Auto => raise native_not_supported("zero-copy open")
  }
  {
    config,
    pool,
    handle_id,
    is_open: true,
    resolved_backend: backend,
  }
}

///|
impl @hal.ZeroCopyNic for NativeZeroCopyNic with acquire_tx(
  self : NativeZeroCopyNic
) -> @hal.FrameRef raise @hal.EcError {
  self.pool.acquire()
}

///|
impl @hal.ZeroCopyNic for NativeZeroCopyNic with tx_buffer(
  self : NativeZeroCopyNic,
  fref : @hal.FrameRef
) -> FixedArray[Byte] {
  self.pool.buffer(fref)
}

///|
impl @hal.ZeroCopyNic for NativeZeroCopyNic with submit(
  self : NativeZeroCopyNic,
  fref : @hal.FrameRef,
  length~ : Int
) -> Unit raise @hal.EcError {
  let buf = self.pool.buffer(fref)
  match self.resolved_backend {
    WindowsNpcap => {
      let _ = npcap_send_zero_copy(self.handle_id, buf, length)

    }
    LinuxRawSocket => {
      let _ = linux_send_zero_copy(self.handle_id, buf, length)

    }
    Auto => raise native_not_supported("zero-copy submit")
  }
  self.pool.mark_sent(fref)
  self.pool.release(fref)
}

///|
impl @hal.ZeroCopyNic for NativeZeroCopyNic with recv(
  self : NativeZeroCopyNic,
  timeout~ : @hal.Duration
) -> @hal.FrameRef raise @hal.EcError {
  let _ = timeout
  let rx_ref = self.pool.acquire_rx()
  let buf = self.pool.buffer(rx_ref)
  let max_len = self.pool.frame_size
  let length = match self.resolved_backend {
    WindowsNpcap => npcap_recv_zero_copy(self.handle_id, buf, max_len)
    LinuxRawSocket => linux_recv_zero_copy(self.handle_id, buf, max_len)
    Auto => raise native_not_supported("zero-copy recv")
  }
  self.pool.mark_received(rx_ref, length)
}

///|
impl @hal.ZeroCopyNic for NativeZeroCopyNic with rx_buffer(
  self : NativeZeroCopyNic,
  fref : @hal.FrameRef
) -> FixedArray[Byte] {
  self.pool.buffer(fref)
}

///|
impl @hal.ZeroCopyNic for NativeZeroCopyNic with rx_length(
  self : NativeZeroCopyNic,
  fref : @hal.FrameRef
) -> Int {
  self.pool.data_length(fref)
}

///|
impl @hal.ZeroCopyNic for NativeZeroCopyNic with release(
  self : NativeZeroCopyNic,
  fref : @hal.FrameRef
) -> Unit {
  self.pool.release(fref)
}

///|
impl @hal.ZeroCopyNic for NativeZeroCopyNic with close(
  self : NativeZeroCopyNic
) -> Unit {
  if self.is_open {
    match self.resolved_backend {
      WindowsNpcap => ffi_windows_npcap_close(self.handle_id)
      LinuxRawSocket => ffi_linux_raw_socket_close(self.handle_id)
      _ => ()
    }
    self.is_open = false
    self.handle_id = 0
    self.pool.reset()
  }
}

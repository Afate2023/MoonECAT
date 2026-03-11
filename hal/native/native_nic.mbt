///|
pub fn default_native_config(interface_name : String) -> NativeNicConfig {
  {
    interface_name,
    backend: Auto,
    snaplen: @hal.max_frame_size,
    promisc: true,
    timeout_ms: 50,
  }
}

///|
pub fn default_linux_config(interface_name : String) -> NativeNicConfig {
  { ..default_native_config(interface_name), backend: LinuxRawSocket }
}

///|
pub fn default_windows_npcap_config(interface_name : String) -> NativeNicConfig {
  { ..default_native_config(interface_name), backend: WindowsNpcap }
}

///|
pub fn NativeNic::new(config : NativeNicConfig) -> NativeNic {
  { config, handle_id: 0, is_open: false }
}

///|
fn native_not_ready(action : String) -> @hal.EcError {
  @hal.EcError::NotSupported(
    "native backend scaffold is present but platform binding is not implemented for " +
    action,
  )
}

///|
pub fn native_backend_available(backend : NativeBackendKind) -> Bool {
  match backend {
    Auto => windows_npcap_runtime_available()
    WindowsNpcap => windows_npcap_runtime_available()
    LinuxRawSocket => false
  }
}

///|
pub fn NativeNic::open_with_config(
  config : NativeNicConfig,
) -> NativeNic raise @hal.EcError {
  match config.backend {
    Auto =>
      if windows_npcap_runtime_available() {
        let resolved = { ..config, backend: WindowsNpcap }
        let handle_id = windows_npcap_open(resolved)
        { config: resolved, handle_id, is_open: true }
      } else {
        raise native_not_ready("open")
      }
    WindowsNpcap => {
      let handle_id = windows_npcap_open(config)
      { config, handle_id, is_open: true }
    }
    LinuxRawSocket => raise native_not_ready("open Linux Raw Socket")
  }
}

///|
pub impl @hal.Nic for NativeNic with open_(name) {
  NativeNic::open_with_config(default_native_config(name))
}

///|
pub impl @hal.Nic for NativeNic with send(self, data) {
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  match self.config.backend {
    WindowsNpcap => windows_npcap_send(self.handle_id, data)
    Auto => raise native_not_ready("send")
    LinuxRawSocket => raise native_not_ready("send Linux Raw Socket")
  }
}

///|
pub impl @hal.Nic for NativeNic with recv(self, timeout~) {
  ignore(timeout)
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  match self.config.backend {
    WindowsNpcap => windows_npcap_recv(self.handle_id)
    Auto => raise native_not_ready("recv")
    LinuxRawSocket => raise native_not_ready("recv Linux Raw Socket")
  }
}

///|
pub impl @hal.Nic for NativeNic with close(self) {
  if self.is_open {
    match self.config.backend {
      WindowsNpcap => windows_npcap_close(self.handle_id)
      _ => ()
    }
  }
  self.handle_id = 0
  self.is_open = false
}

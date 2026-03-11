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
fn native_not_supported(action : String) -> @hal.EcError {
  @hal.EcError::NotSupported("native backend is not available for " + action)
}

///|
fn resolve_native_backend(
  backend : NativeBackendKind,
) -> NativeBackendKind raise @hal.EcError {
  match backend {
    Auto =>
      if windows_npcap_runtime_available() {
        WindowsNpcap
      } else if linux_raw_socket_runtime_available() {
        LinuxRawSocket
      } else {
        raise native_not_supported("automatic backend selection")
      }
    _ => backend
  }
}

///|
pub fn native_list_interfaces_text(
  backend : NativeBackendKind,
) -> String raise @hal.EcError {
  match resolve_native_backend(backend) {
    Auto => raise native_not_supported("list interfaces")
    WindowsNpcap => windows_npcap_list_interfaces_text()
    LinuxRawSocket => linux_raw_socket_list_interfaces_text()
  }
}

///|
pub fn native_list_interfaces_json(
  backend : NativeBackendKind,
) -> String raise @hal.EcError {
  match resolve_native_backend(backend) {
    Auto => raise native_not_supported("list interfaces")
    WindowsNpcap => windows_npcap_list_interfaces_json()
    LinuxRawSocket => linux_raw_socket_list_interfaces_json()
  }
}

///|
pub fn native_backend_available(backend : NativeBackendKind) -> Bool {
  match backend {
    Auto =>
      windows_npcap_runtime_available() || linux_raw_socket_runtime_available()
    WindowsNpcap => windows_npcap_runtime_available()
    LinuxRawSocket => linux_raw_socket_runtime_available()
  }
}

///|
pub fn NativeNic::open_with_config(
  config : NativeNicConfig,
) -> NativeNic raise @hal.EcError {
  match resolve_native_backend(config.backend) {
    Auto => raise native_not_supported("open")
    WindowsNpcap => {
      let resolved = { ..config, backend: WindowsNpcap }
      let handle_id = windows_npcap_open(resolved)
      { config: resolved, handle_id, is_open: true }
    }
    LinuxRawSocket => {
      let resolved = { ..config, backend: LinuxRawSocket }
      let handle_id = linux_raw_socket_open(resolved)
      { config: resolved, handle_id, is_open: true }
    }
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
    Auto => raise native_not_supported("send")
    LinuxRawSocket => linux_raw_socket_send(self.handle_id, data)
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
    Auto => raise native_not_supported("recv")
    LinuxRawSocket => linux_raw_socket_recv(self.handle_id)
  }
}

///|
pub impl @hal.Nic for NativeNic with close(self) {
  if self.is_open {
    match self.config.backend {
      WindowsNpcap => windows_npcap_close(self.handle_id)
      LinuxRawSocket => linux_raw_socket_close(self.handle_id)
      _ => ()
    }
  }
  self.handle_id = 0
  self.is_open = false
}

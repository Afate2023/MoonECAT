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
  {
    config,
    handle_id: 0,
    is_open: false,
    last_sent: Bytes::new(0),
    next_datagram_index: 0,
    protocol_datagram_indices: [],
    wire_datagram_indices: [],
  }
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
pub fn native_list_interfaces(
  backend : NativeBackendKind,
) -> NativeInterfaceListing raise @hal.EcError {
  let parsed = @json.parse(native_list_interfaces_json(backend)[:]) catch {
    err =>
      raise @hal.EcError::Internal(
        "native interface listing parse failed: " + err.to_string(),
      )
  }
  parse_native_interface_listing(parsed)
}

///|
pub fn native_interface_is_probe_candidate(
  interface : NativeInterfaceInfo,
) -> Bool {
  !interface.loopback &&
  !interface.wireless &&
  interface.up &&
  interface.connected
}

///|
pub fn native_interface_probe_candidates(
  listing : NativeInterfaceListing,
) -> Array[NativeInterfaceInfo] {
  listing.interfaces.filter(fn(interface) {
    native_interface_is_probe_candidate(interface)
  })
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
pub fn parse_native_interface_listing(
  json : Json,
) -> NativeInterfaceListing raise @hal.EcError {
  guard json
    is { "backend": backend_json, "interfaces": Array(interfaces_json), .. } else {
    raise @hal.EcError::ConfigMismatch(
      "native interface listing decode failed: missing backend or interfaces",
    )
  }
  {
    backend: decode_native_interface_backend(backend_json),
    interfaces: interfaces_json.map(interface_json => {
      parse_native_interface_info(interface_json)
    }),
  }
}

///|
fn parse_native_interface_info(
  json : Json,
) -> NativeInterfaceInfo raise @hal.EcError {
  guard json
    is {
      "name": name_json,
      "description"? : description_json,
      "loopback"? : loopback_json,
      "up"? : up_json,
      "connected"? : connected_json,
      "wireless"? : wireless_json,
      "index"? : index_json,
      ..
    } else {
    raise @hal.EcError::ConfigMismatch(
      "native interface listing decode failed: invalid interface entry",
    )
  }
  {
    name: decode_native_interface_string(name_json),
    description: decode_optional_native_interface_string(description_json, ""),
    loopback: decode_optional_native_interface_bool(loopback_json, false),
    up: decode_optional_native_interface_bool(up_json, true),
    connected: decode_optional_native_interface_bool(connected_json, true),
    wireless: decode_optional_native_interface_bool(wireless_json, false),
    index: decode_optional_native_interface_int(index_json),
  }
}

///|
fn decode_native_interface_backend(
  json : Json,
) -> NativeBackendKind raise @hal.EcError {
  match decode_native_interface_string(json) {
    "native" => Auto
    "native-windows-npcap" => WindowsNpcap
    "native-linux-raw" => LinuxRawSocket
    backend =>
      raise @hal.EcError::ConfigMismatch(
        "native interface listing decode failed: unknown backend " + backend,
      )
  }
}

///|
fn decode_native_interface_string(json : Json) -> String raise @hal.EcError {
  @json.from_json(json) catch {
    err =>
      raise @hal.EcError::ConfigMismatch(
        "native interface listing decode failed: " + err.to_string(),
      )
  }
}

///|
fn decode_optional_native_interface_string(
  json : Json?,
  default : String,
) -> String raise @hal.EcError {
  match json {
    None | Some(Null) => default
    Some(value) => decode_native_interface_string(value)
  }
}

///|
fn decode_optional_native_interface_bool(
  json : Json?,
  default : Bool,
) -> Bool raise @hal.EcError {
  match json {
    None | Some(Null) => default
    Some(value) =>
      @json.from_json(value) catch {
        err =>
          raise @hal.EcError::ConfigMismatch(
            "native interface listing decode failed: " + err.to_string(),
          )
      }
  }
}

///|
fn decode_optional_native_interface_int(
  json : Json?,
) -> Int? raise @hal.EcError {
  match json {
    None | Some(Null) => None
    Some(value) =>
      Some(
        @json.from_json(value) catch {
          err =>
            raise @hal.EcError::ConfigMismatch(
              "native interface listing decode failed: " + err.to_string(),
            )
        },
      )
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
      {
        config: resolved,
        handle_id,
        is_open: true,
        last_sent: Bytes::new(0),
        next_datagram_index: 0,
        protocol_datagram_indices: [],
        wire_datagram_indices: [],
      }
    }
    LinuxRawSocket => {
      let resolved = { ..config, backend: LinuxRawSocket }
      let handle_id = linux_raw_socket_open(resolved)
      {
        config: resolved,
        handle_id,
        is_open: true,
        last_sent: Bytes::new(0),
        next_datagram_index: 0,
        protocol_datagram_indices: [],
        wire_datagram_indices: [],
      }
    }
  }
}

///|
pub impl @hal.Nic for NativeNic with fn open_(name) {
  NativeNic::open_with_config(default_native_config(name))
}

///|
/// Return the byte offsets of all EtherCAT datagram index fields.
/// Invalid or non-EtherCAT frames return an empty list and pass through unchanged.
fn native_datagram_index_offsets(data : Bytes) -> Array[Int] {
  let offsets : Array[Int] = []
  if data.length() < 16 || data[12] != b'\x88' || data[13] != b'\xA4' {
    return offsets
  }
  let ecat_header = data[14].to_int() | (data[15].to_int() << 8)
  let payload_length = ecat_header & 0x7FF
  let payload_end = 16 + payload_length
  if payload_length == 0 || payload_end > data.length() {
    return offsets
  }
  let mut offset = 16
  while offset < payload_end {
    if offset + 10 > payload_end {
      return []
    }
    let len_flags = data[offset + 6].to_int() | (data[offset + 7].to_int() << 8)
    let data_length = len_flags & 0x7FF
    let datagram_end = offset + 10 + data_length + 2
    if datagram_end > payload_end {
      return []
    }
    offsets.push(offset + 1)
    offset = datagram_end
    if (len_flags & 0x8000) == 0 {
      break
    }
  }
  offsets
}

///|
/// Replace protocol-layer datagram indices with a NativeNic-local wire sequence.
fn prepare_native_send(
  data : Bytes,
  next_index : Int,
) -> (Bytes, Array[Byte], Array[Byte], Int) {
  let offsets = native_datagram_index_offsets(data)
  if offsets.is_empty() {
    return (data, [], [], next_index)
  }
  let frame = FixedArray::make(data.length(), b'\x00')
  for i in 0..<data.length() {
    frame[i] = data[i]
  }
  let protocol_indices : Array[Byte] = []
  let wire_indices : Array[Byte] = []
  let mut current = next_index
  for offset in offsets {
    let protocol_index = data[offset]
    let wire_index = (current & 0xFF).to_byte()
    protocol_indices.push(protocol_index)
    wire_indices.push(wire_index)
    frame[offset] = wire_index
    current = (current + 1) & 0xFF
  }
  (Bytes::from_array(frame), protocol_indices, wire_indices, current)
}

///|
/// Restore wire indices before returning a response to the protocol layer.
/// A frame with different indices is unrelated and remains unchanged.
fn restore_native_response_indices(
  data : Bytes,
  protocol_indices : Array[Byte],
  wire_indices : Array[Byte],
) -> Bytes {
  let offsets = native_datagram_index_offsets(data)
  if offsets.length() != wire_indices.length() ||
    protocol_indices.length() != wire_indices.length() {
    return data
  }
  for i, offset in offsets {
    if data[offset] != wire_indices[i] {
      return data
    }
  }
  let frame = FixedArray::make(data.length(), b'\x00')
  for i in 0..<data.length() {
    frame[i] = data[i]
  }
  for i, offset in offsets {
    frame[offset] = protocol_indices[i]
  }
  Bytes::from_array(frame)
}

///|
pub impl @hal.Nic for NativeNic with fn send(self, data) {
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  let (wire_data, protocol_indices, wire_indices, next_index) = prepare_native_send(
    data,
    self.next_datagram_index,
  )
  self.last_sent = wire_data
  self.protocol_datagram_indices = protocol_indices
  self.wire_datagram_indices = wire_indices
  self.next_datagram_index = next_index
  match self.config.backend {
    WindowsNpcap => windows_npcap_send(self.handle_id, wire_data)
    Auto => raise native_not_supported("send")
    LinuxRawSocket => linux_raw_socket_send(self.handle_id, wire_data)
  }
}

///|
pub impl @hal.Nic for NativeNic with fn recv(self, timeout~) {
  ignore(timeout)
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  for _attempt = 0; _attempt < 4; _attempt = _attempt + 1 {
    let response = match self.config.backend {
      WindowsNpcap => windows_npcap_recv(self.handle_id)
      Auto => raise native_not_supported("recv")
      LinuxRawSocket => linux_raw_socket_recv(self.handle_id)
    }
    if response == self.last_sent {
      continue
    }
    return restore_native_response_indices(
      response,
      self.protocol_datagram_indices,
      self.wire_datagram_indices,
    )
  }
  raise @hal.EcError::RecvTimeout
}

///|
pub impl @hal.Nic for NativeNic with fn close(self) {
  if self.is_open {
    match self.config.backend {
      WindowsNpcap => windows_npcap_close(self.handle_id)
      LinuxRawSocket => linux_raw_socket_close(self.handle_id)
      _ => ()
    }
  }
  self.handle_id = 0
  self.is_open = false
  self.last_sent = Bytes::new(0)
  self.next_datagram_index = 0
  self.protocol_datagram_indices.clear()
  self.wire_datagram_indices.clear()
}

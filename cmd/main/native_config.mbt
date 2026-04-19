///|
fn parse_backend(args : Array[String]) -> CliBackend raise @hal.EcError {
  match flag_value(args, "--backend") {
    Some("mock") | None => Mock
    Some("native") => NativeAuto
    Some("native-windows-npcap") => NativeWindowsNpcap
    Some("native-linux-raw") => NativeLinuxRaw
    Some(other) =>
      raise @hal.EcError::ConfigMismatch("unsupported backend: " + other)
  }
}

///|
fn require_interface_name(args : Array[String]) -> String raise @hal.EcError {
  match flag_value(args, "--if") {
    Some(name) => name
    None =>
      raise @hal.EcError::ConfigMismatch(
        "native backend requires --if <interface>",
      )
  }
}

///|
fn resolve_native_cli_config(
  args : Array[String],
  backend : CliBackend,
  timeout : @hal.Duration,
) -> @native.NativeNicConfig raise @hal.EcError {
  let requested_backend = cli_backend_to_native_backend(backend)
  match flag_value(args, "--if") {
    Some(_) =>
      native_config_for_backend(requested_backend, require_interface_name(args))
    None => auto_select_native_cli_config(requested_backend, timeout)
  }
}

///|
fn native_config_for_backend(
  backend : @native.NativeBackendKind,
  interface_name : String,
) -> @native.NativeNicConfig {
  match backend {
    @native.Auto => @native.default_native_config(interface_name)
    @native.WindowsNpcap => @native.default_windows_npcap_config(interface_name)
    @native.LinuxRawSocket => @native.default_linux_config(interface_name)
  }
}

///|
fn auto_select_native_cli_config(
  backend : @native.NativeBackendKind,
  timeout : @hal.Duration,
) -> @native.NativeNicConfig raise @hal.EcError {
  let listing = @native.native_list_interfaces(backend)
  select_native_cli_config_from_listing(listing, timeout, fn(config, timeout) {
    probe_native_cli_config(config, timeout)
  })
}

///|
fn select_native_cli_config_from_listing(
  listing : @native.NativeInterfaceListing,
  timeout : @hal.Duration,
  probe : (@native.NativeNicConfig, @hal.Duration) -> Result[Int, Error],
) -> @native.NativeNicConfig raise @hal.EcError {
  let candidates = @native.native_interface_probe_candidates(listing)
  if candidates.is_empty() {
    raise @hal.EcError::ConfigMismatch(
      "automatic native interface selection found no connected non-wireless candidates; pass --if <interface> or inspect list-if --json",
    )
  }
  let notes : Array[String] = []
  for interface in listing.interfaces {
    if !@native.native_interface_is_probe_candidate(interface) {
      notes.push(
        interface.name + "(" + skipped_native_interface_reason(interface) + ")",
      )
    }
  }
  for candidate in candidates {
    let config = native_config_for_backend(listing.backend, candidate.name)
    match probe(config, timeout) {
      Ok(slave_count) if slave_count > 0 => return config
      Ok(_) => notes.push(candidate.name + "(no-response)")
      Err(err) =>
        notes.push(candidate.name + "(" + native_probe_error_label(err) + ")")
    }
  }
  raise @hal.EcError::ConfigMismatch(
    "automatic native interface selection found no EtherCAT BRD response: " +
    join_cli_notes(notes),
  )
}

///|
fn probe_native_cli_config(
  config : @native.NativeNicConfig,
  timeout : @hal.Duration,
) -> Result[Int, Error] {
  let open_result : Result[@native.NativeNic, Error] = try? @native.NativeNic::open_with_config(
    config,
  )
  match open_result {
    Ok(nic) => {
      let probe_result : Result[Int, Error] = try? @protocol.count_slaves(
        nic, timeout,
      )
      nic.close()
      probe_result
    }
    Err(err) => Err(err)
  }
}

///|
fn skipped_native_interface_reason(
  interface : @native.NativeInterfaceInfo,
) -> String {
  if interface.loopback {
    return "loopback"
  }
  if interface.wireless {
    return "wireless"
  }
  if !interface.up {
    return "down"
  }
  if !interface.connected {
    return "disconnected"
  }
  "filtered"
}

///|
fn native_probe_error_label(err : Error) -> String {
  match err {
    @hal.EcError::LinkDown => "link-down"
    @hal.EcError::RecvTimeout => "recv-timeout"
    @hal.EcError::ConfigMismatch(message) => "config:" + message
    @hal.EcError::NotSupported(message) => "unsupported:" + message
    @hal.EcError::SendFailed(message) => "send:" + message
    @hal.EcError::RecvFailed(message) => "recv:" + message
    @hal.EcError::Internal(message) => "internal:" + message
    other => other.to_string()
  }
}

///|
fn join_cli_notes(values : Array[String]) -> String {
  let mut text = ""
  for i = 0; i < values.length(); i = i + 1 {
    if i > 0 {
      text = text + ", "
    }
    text = text + values[i]
  }
  text
}

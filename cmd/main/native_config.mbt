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
struct ExternalHarnessConfig {
  backend : CliBackend
  interface_name : String
  backend_label : String
  driver_id : String
  session_id : String
  harness_package : String
  pending_reason : String
} derive(Eq, Debug)

///|
fn resolve_native_cli_config(
  args : Array[String],
  backend : CliBackend,
  timeout : @hal.Duration,
) -> ExternalHarnessConfig raise @hal.EcError {
  ignore(timeout)
  match flag_value(args, "--if") {
    Some(_) => native_config_for_backend(backend, require_interface_name(args))
    None =>
      raise @hal.EcError::ConfigMismatch(
        "native backend moved to provider harness; pass --if <interface> to prepare a handoff descriptor or run fieldbus_core/moonecat_master_harness",
      )
  }
}

///|
fn native_config_for_backend(
  backend : CliBackend,
  interface_name : String,
) -> ExternalHarnessConfig raise @hal.EcError {
  match backend {
    Mock =>
      raise @hal.EcError::NotSupported("mock backend has no native harness")
    _ =>
      {
        backend,
        interface_name,
        backend_label: native_backend_label(backend),
        driver_id: native_driver_id(backend),
        session_id: native_session_id(backend),
        harness_package: "fieldbus_core/moonecat_master_harness",
        pending_reason: "MoonECAT native CLI entry moved to provider-owned Lockwire session harness",
      }
  }
}

///|
fn native_backend_label(backend : CliBackend) -> String {
  match backend {
    Mock => "mock"
    NativeAuto => "native"
    NativeWindowsNpcap => "native-windows-npcap"
    NativeLinuxRaw => "native-linux-raw"
  }
}

///|
fn native_driver_id(backend : CliBackend) -> String {
  match backend {
    Mock => ""
    NativeAuto =>
      "moonecat.windows_npcap.raw_frame|moonecat.linux_raw_socket.raw_frame"
    NativeWindowsNpcap => "moonecat.windows_npcap.raw_frame"
    NativeLinuxRaw => "moonecat.linux_raw_socket.raw_frame"
  }
}

///|
fn native_session_id(backend : CliBackend) -> String {
  match backend {
    Mock => ""
    NativeAuto => "native.link-session.npcap|native.link-session.raw-socket"
    NativeWindowsNpcap => "native.link-session.npcap"
    NativeLinuxRaw => "native.link-session.raw-socket"
  }
}

///|
fn native_harness_pending_message(
  command : String,
  config : ExternalHarnessConfig,
) -> String {
  command +
  " native backend moved to provider harness " +
  config.harness_package +
  " (backend=" +
  config.backend_label +
  ", interface=" +
  config.interface_name +
  ", driver=" +
  config.driver_id +
  ", session=" +
  config.session_id +
  ")"
}

///|
fn raise_native_harness_pending(
  command : String,
  config : ExternalHarnessConfig,
) -> Unit raise @hal.EcError {
  raise @hal.EcError::NotSupported(
    native_harness_pending_message(command, config),
  )
}

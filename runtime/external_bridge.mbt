///|
/// CoSimAdapter external process bridge.
///
/// C-11: Bridges MoonECAT's CoSimAdapter trait to an external process
/// (Simulink, Modelica, custom C model) via:
///   - Unix domain socket (Linux/macOS)
///   - Named pipe (Windows)
///   - Shared memory + semaphore (low-latency variant)
///
/// Wire protocol (per step):
///   Request:  [8B sim_time_ns][8B dt_ns][NB outputs_data]
///   Response: [1B status][NB inputs_data][optional: 8B new_sim_time]
///
/// Status byte values:
///   0x00 = OK
///   0x01 = Terminated (followed by NUL-terminated reason string)
///   0xFF = Error (followed by NUL-terminated message)

///|
/// Transport type for the external process bridge.
pub(all) enum BridgeTransport {
  /// Unix domain socket at the given path.
  UnixSocket(String)
  /// Named pipe (Windows).
  NamedPipe(String)
  /// Shared memory region + semaphore pair.
  SharedMemory(name~ : String, size~ : Int)
} derive(Show)

///|
/// Configuration for the external process bridge.
pub(all) struct ExternalBridgeConfig {
  /// Transport mechanism.
  transport : BridgeTransport
  /// Timeout per step call in nanoseconds (0 = no timeout).
  step_timeout_ns : Int64
  /// Whether to launch the external process automatically.
  auto_launch : Bool
  /// Command to launch the external process (if auto_launch).
  launch_command : String
  /// Working directory for the external process.
  launch_cwd : String
} derive(Show)

///|
pub fn ExternalBridgeConfig::unix_socket(path : String) -> ExternalBridgeConfig {
  {
    transport: UnixSocket(path),
    step_timeout_ns: 1_000_000_000L,
    auto_launch: false,
    launch_command: "",
    launch_cwd: "",
  }
}

///|
pub fn ExternalBridgeConfig::named_pipe(name : String) -> ExternalBridgeConfig {
  {
    transport: NamedPipe(name),
    step_timeout_ns: 1_000_000_000L,
    auto_launch: false,
    launch_command: "",
    launch_cwd: "",
  }
}

///|
pub fn ExternalBridgeConfig::shared_memory(
  name : String,
  size : Int,
) -> ExternalBridgeConfig {
  {
    transport: SharedMemory(name~, size~),
    step_timeout_ns: 500_000_000L,
    auto_launch: false,
    launch_command: "",
    launch_cwd: "",
  }
}

///|
/// Connection state of the external bridge.
pub(all) enum BridgeState {
  /// Not yet connected.
  Disconnected
  /// Connected and ready for step calls.
  Connected
  /// External process terminated.
  Terminated(String)
  /// Communication error occurred.
  Error(String)
} derive(Eq, Show)

///|
/// ExternalProcessBridge — CoSimAdapter that delegates to an external process.
///
/// This struct manages the connection lifecycle and serialization.
/// Actual I/O operations are delegated to platform-specific extern "c" stubs.
pub(all) struct ExternalProcessBridge {
  config : ExternalBridgeConfig
  mut state : BridgeState
  /// Output buffer size (from CoSimConfig).
  mut output_size : Int
  /// Input buffer size (from CoSimConfig).
  mut input_size : Int
  /// Accumulated round-trip latencies for diagnostics.
  mut step_count : Int64
  mut total_latency_ns : Int64
} derive(Show)

///|
pub fn ExternalProcessBridge::new(
  config : ExternalBridgeConfig,
) -> ExternalProcessBridge {
  {
    config,
    state: Disconnected,
    output_size: 0,
    input_size: 0,
    step_count: 0L,
    total_latency_ns: 0L,
  }
}

///|
/// Average round-trip latency in nanoseconds.
pub fn ExternalProcessBridge::avg_latency_ns(
  self : ExternalProcessBridge,
) -> Int64 {
  if self.step_count == 0L {
    0L
  } else {
    self.total_latency_ns / self.step_count
  }
}

///|
/// Encode a step request into the wire protocol format.
///
/// Format: [8B sim_time_ns LE][8B dt_ns LE][output_size B outputs]
pub fn encode_step_request(
  sim_time_ns : Int64,
  dt_ns : Int64,
  outputs : Bytes,
  output_size : Int,
) -> Bytes {
  let total = 16 + output_size
  let copy_len = if outputs.length() < output_size {
    outputs.length()
  } else {
    output_size
  }
  Bytes::makei(total, fn(i) {
    if i < 8 {
      (sim_time_ns >> (i * 8)).to_byte()
    } else if i < 16 {
      (dt_ns >> ((i - 8) * 8)).to_byte()
    } else if i - 16 < copy_len {
      outputs[i - 16]
    } else {
      b'\x00'
    }
  })
}

///|
/// Decode a step response from the wire protocol format.
///
/// Format: [1B status][input_size B inputs][optional tail]
/// Returns: (status_byte, input_data)
pub fn decode_step_response(data : Bytes, input_size : Int) -> (Byte, Bytes) {
  if data.length() < 1 {
    return (b'\xFF', Bytes::make(input_size, b'\x00'))
  }
  let status = data[0]
  let has_data = data.length() >= 1 + input_size
  let inputs = Bytes::makei(input_size, fn(i) {
    if has_data {
      data[1 + i]
    } else {
      b'\x00'
    }
  })
  (status, inputs)
}

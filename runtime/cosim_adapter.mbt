///|
/// Co-simulation adapter contract for HIL (Hardware-in-the-Loop) integration.
///
/// This module defines the trait-based boundary between MoonECAT's runtime
/// and external plant/controller models (Simulink, Modelica, custom C code).
///
/// Architecture:
///   MoonECAT Runtime ←→ CoSimAdapter ←→ External Plant/Controller
///
/// The adapter translates between:
///   - EtherCAT process image bytes (outputs/inputs)
///   - Physical quantities the plant model consumes/produces
///
/// Zero-copy principle:
///   The adapter receives direct references to ProcessImage slices;
///   no intermediate serialization unless the external model requires it.

///|
/// SimTime represents simulation time in nanoseconds since simulation start.
/// Distinct from HAL Timestamp to decouple real-time from simulated time.
pub(all) struct SimTime(Int64) derive(Eq, Show, Compare)

///|
pub fn SimTime::zero() -> SimTime {
  SimTime(0L)
}

///|
pub fn SimTime::from_ns(ns : Int64) -> SimTime {
  SimTime(ns)
}

///|
pub fn SimTime::to_ns(self : SimTime) -> Int64 {
  self.0
}

///|
pub fn SimTime::advance(self : SimTime, delta_ns : Int64) -> SimTime {
  SimTime(self.0 + delta_ns)
}

///|
/// SimStepResult reports the outcome of one simulation step.
pub(all) enum SimStepResult {
  /// Step completed normally; simulation time advanced.
  Ok(SimTime)
  /// Plant model reports a termination condition (e.g., collision, limit hit).
  Terminated(String)
  /// Simulation error (e.g., solver divergence).
  Error(String)
} derive(Eq, Show)

///|
/// CoSimAdapter — the trait that external plant/controller models implement.
///
/// Lifecycle:
///   1. `init(config)` — one-time initialization with cycle period and PI layout
///   2. Per cycle: `write_outputs(image, slice)` → `step(dt)` → `read_inputs(image, slice)`
///   3. `shutdown()` — cleanup
///
/// The runtime invokes these in deterministic order within each CycleHook callback.
pub(open) trait CoSimAdapter {
  /// Initialize the adapter with simulation parameters.
  init_(Self, CoSimConfig) -> Unit

  /// Write EtherCAT outputs into the plant model's input ports.
  /// Called before `step()`. The adapter reads from `image.outputs` at the
  /// given slice region and translates to physical quantities.
  write_outputs(Self, @protocol.ProcessImage, ProcessImageSlice) -> Unit

  /// Advance the plant model by one time step.
  step(Self, SimTime, Int64) -> SimStepResult

  /// Read plant model outputs back into EtherCAT inputs.
  /// Called after `step()`. The adapter writes to `image.inputs` at the
  /// given slice region.
  read_inputs(Self, @protocol.ProcessImage, ProcessImageSlice) -> Unit

  /// One-time cleanup.
  shutdown(Self) -> Unit
}

///|
/// CoSimConfig provides the adapter with the simulation parameters it needs.
pub(all) struct CoSimConfig {
  /// Base cycle period in nanoseconds.
  cycle_period_ns : Int64
  /// Number of slaves in the configuration.
  slave_count : Int
  /// Total output image size in bytes.
  output_size : Int
  /// Total input image size in bytes.
  input_size : Int
} derive(Eq, Show)

///|
/// LoopbackCoSimAdapter — trivial adapter that copies outputs to inputs.
/// Useful for communication-closed-loop testing without an external model.
pub struct LoopbackCoSimAdapter {
  mut sim_time : SimTime
}

///|
pub fn LoopbackCoSimAdapter::new() -> LoopbackCoSimAdapter {
  { sim_time: SimTime::zero() }
}

///|
pub impl CoSimAdapter for LoopbackCoSimAdapter with init_(self, _config) {
  ignore(self)
}

///|
pub impl CoSimAdapter for LoopbackCoSimAdapter with write_outputs(
  self,
  _image,
  _slice,
) {
  ignore(self)
}

///|
pub impl CoSimAdapter for LoopbackCoSimAdapter with step(self, current, dt) {
  self.sim_time = current.advance(dt)
  Ok(self.sim_time)
}

///|
pub impl CoSimAdapter for LoopbackCoSimAdapter with read_inputs(
  self,
  image,
  slice,
) {
  ignore(self)
  // Copy outputs to inputs (loopback)
  let len = if slice.output_length < slice.input_length {
    slice.output_length
  } else {
    slice.input_length
  }
  let buf = @buffer.new(size_hint=image.input_size)
  for i = 0; i < image.input_size; i = i + 1 {
    if i >= slice.input_offset && i < slice.input_offset + len {
      buf.write_byte(
        image.outputs[slice.output_offset + (i - slice.input_offset)],
      )
    } else {
      buf.write_byte(image.inputs[i])
    }
  }
  image.inputs = buf.to_bytes()
}

///|
pub impl CoSimAdapter for LoopbackCoSimAdapter with shutdown(self) {
  ignore(self)
}

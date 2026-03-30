///|
/// ProcessImageSlice — a zero-copy view into a contiguous region of a ProcessImage.
///
/// Design rationale:
///   - HIL and multi-axis systems need isolated access to subsets of the PI
///   - Each task/controller owns one or more slices without copying
///   - Slices are bounded and checked at creation, not at every access
///   - Maps directly to DMA descriptor regions on MCU targets
///
/// Safety: offsets are validated at slice creation; subsequent access is
/// bounds-checked by the underlying Bytes API.
pub(all) struct ProcessImageSlice {
  /// Byte offset into the parent ProcessImage outputs.
  output_offset : Int
  /// Number of output bytes in this slice.
  output_length : Int
  /// Byte offset into the parent ProcessImage inputs.
  input_offset : Int
  /// Number of input bytes in this slice.
  input_length : Int
} derive(Eq, Show)

///|
/// TaskDescriptor identifies a logical task that owns one PI partition.
///
/// Modeled after IEC 61131-3 task concept:
///   - Each task has a unique name, a priority level, and a cycle divisor
///   - The cycle divisor controls how often the task executes relative to
///     the base EtherCAT cycle (divisor=1 → every cycle, divisor=4 → every 4th)
///   - Priority determines execution order within a single base cycle
pub(all) struct TaskDescriptor {
  /// Unique task name (e.g., "motion_axis_1", "safety_monitor").
  name : String
  /// Task priority (0 = highest / most urgent).
  priority : Int
  /// Cycle divisor relative to the base EtherCAT cycle.
  cycle_divisor : Int
  /// The PI slice this task owns.
  slice : ProcessImageSlice
} derive(Eq, Show)

///|
/// TaskSchedule holds an ordered sequence of tasks, sorted by priority,
/// with the base cycle period from the master configuration.
pub(all) struct TaskSchedule {
  /// Base EtherCAT cycle period in nanoseconds.
  base_period_ns : Int64
  /// Tasks sorted by priority (0 = highest first).
  tasks : Array[TaskDescriptor]
} derive(Eq, Show)

///|
/// Create a ProcessImageSlice from a PdoMapping.
/// Validates that the mapping fits within the given ProcessImage dimensions.
pub fn slice_from_mapping(
  mapping : @protocol.PdoMapping,
  image : @protocol.ProcessImage,
) -> ProcessImageSlice? {
  if mapping.output_offset + mapping.output_length > image.output_size {
    return None
  }
  if mapping.input_offset + mapping.input_length > image.input_size {
    return None
  }
  Some({
    output_offset: mapping.output_offset,
    output_length: mapping.output_length,
    input_offset: mapping.input_offset,
    input_length: mapping.input_length,
  })
}

///|
/// Partition a PdoContext into per-slave slices.
/// Returns an array of (station_address, slice) pairs.
pub fn partition_by_slave(
  ctx : @protocol.PdoContext,
) -> Array[(UInt, ProcessImageSlice)] {
  ctx.mappings.map(fn(m) {
    (
      m.station,
      {
        output_offset: m.output_offset,
        output_length: m.output_length,
        input_offset: m.input_offset,
        input_length: m.input_length,
      },
    )
  })
}

///|
/// Build a TaskSchedule from task descriptors.
/// Validates: no overlapping PI regions, positive divisors, unique names.
/// Returns None if validation fails.
pub fn build_task_schedule(
  base_period_ns : Int64,
  tasks : Array[TaskDescriptor],
) -> TaskSchedule? {
  // Validate positive divisors
  for t in tasks {
    if t.cycle_divisor <= 0 {
      return None
    }
  }
  // Validate unique names
  for i = 0; i < tasks.length(); i = i + 1 {
    for j = i + 1; j < tasks.length(); j = j + 1 {
      if tasks[i].name == tasks[j].name {
        return None
      }
    }
  }
  // Validate no overlapping output regions
  for i = 0; i < tasks.length(); i = i + 1 {
    for j = i + 1; j < tasks.length(); j = j + 1 {
      if slices_overlap_output(tasks[i].slice, tasks[j].slice) {
        return None
      }
    }
  }
  // Sort by priority
  let sorted = tasks.copy()
  sorted.sort_by(fn(a, b) { a.priority.compare(b.priority) })
  Some({ base_period_ns, tasks: sorted })
}

///|
fn slices_overlap_output(a : ProcessImageSlice, b : ProcessImageSlice) -> Bool {
  if a.output_length == 0 || b.output_length == 0 {
    return false
  }
  let a_end = a.output_offset + a.output_length
  let b_end = b.output_offset + b.output_length
  a.output_offset < b_end && b.output_offset < a_end
}

///|
/// Determine which tasks should execute at a given cycle number.
pub fn tasks_due_at_cycle(
  schedule : TaskSchedule,
  cycle : Int64,
) -> Array[TaskDescriptor] {
  schedule.tasks.filter(fn(t) { cycle % t.cycle_divisor.to_int64() == 0L })
}

///|
/// Read input bytes for a slice from a ProcessImage.
pub fn read_slice_inputs(
  image : @protocol.ProcessImage,
  slice : ProcessImageSlice,
) -> Bytes {
  if slice.input_length == 0 {
    return Bytes::new(0)
  }
  Bytes::makei(slice.input_length, fn(i) {
    image.inputs[slice.input_offset + i]
  })
}

///|
/// Write output bytes for a slice into a ProcessImage.
pub fn write_slice_outputs(
  image : @protocol.ProcessImage,
  slice : ProcessImageSlice,
  data : Bytes,
) -> Unit {
  let len = if data.length() < slice.output_length {
    data.length()
  } else {
    slice.output_length
  }
  let buf = @buffer.new(size_hint=image.output_size)
  for i = 0; i < image.output_size; i = i + 1 {
    if i >= slice.output_offset && i < slice.output_offset + len {
      buf.write_byte(data[i - slice.output_offset])
    } else {
      buf.write_byte(image.outputs[i])
    }
  }
  image.outputs = buf.to_bytes()
}

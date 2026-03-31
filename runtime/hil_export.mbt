///|
/// HIL session state export to JSON trace.
///
/// C-14: Exports HilSession state (SimTime + step_log + schedule info)
/// as a structured JSON trace for post-analysis and visualization.
///
/// Output format:
/// {
///   "version": "1.0",
///   "session": { ... },
///   "schedule": { ... },
///   "steps": [ { "index": N, "result": "...", "sim_time_ns": N }, ... ]
/// }

///|
/// Export a HilSession to a JSON trace string.
pub fn hil_session_to_json(session : HilSession) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{\n")
  buf.write_string("  \"version\": \"1.0\",\n")
  // Session metadata
  buf.write_string("  \"session\": {\n")
  buf.write_string(
    "    \"sim_time_ns\": " + session.sim_time.to_ns().to_string() + ",\n",
  )
  buf.write_string(
    "    \"cycle_period_ns\": " + session.cycle_period_ns.to_string() + ",\n",
  )
  buf.write_string(
    "    \"terminated\": " + session.terminated.to_string() + ",\n",
  )
  buf.write_string(
    "    \"termination_reason\": \"" +
    escape_json(session.termination_reason) +
    "\",\n",
  )
  buf.write_string(
    "    \"total_steps\": " + session.step_log.length().to_string() + "\n",
  )
  buf.write_string("  },\n")
  // Schedule
  buf.write_string("  \"schedule\": {\n")
  buf.write_string(
    "    \"base_period_ns\": " +
    session.schedule.base_period_ns.to_string() +
    ",\n",
  )
  buf.write_string("    \"tasks\": [\n")
  for i, t in session.schedule.tasks {
    buf.write_string("      {\n")
    buf.write_string("        \"name\": \"" + escape_json(t.name) + "\",\n")
    buf.write_string("        \"priority\": " + t.priority.to_string() + ",\n")
    buf.write_string(
      "        \"cycle_divisor\": " + t.cycle_divisor.to_string() + "\n",
    )
    buf.write_string("      }")
    if i < session.schedule.tasks.length() - 1 {
      buf.write_string(",")
    }
    buf.write_string("\n")
  }
  buf.write_string("    ]\n")
  buf.write_string("  },\n")
  // Step log
  buf.write_string("  \"steps\": [\n")
  for i, step in session.step_log {
    buf.write_string("    {\n")
    buf.write_string("      \"index\": " + i.to_string() + ",\n")
    let (status, detail, time_ns) = step_result_to_parts(step)
    buf.write_string("      \"status\": \"" + status + "\",\n")
    if detail.length() > 0 {
      buf.write_string("      \"detail\": \"" + escape_json(detail) + "\",\n")
    }
    buf.write_string("      \"sim_time_ns\": " + time_ns.to_string() + "\n")
    buf.write_string("    }")
    if i < session.step_log.length() - 1 {
      buf.write_string(",")
    }
    buf.write_string("\n")
  }
  buf.write_string("  ]\n")
  buf.write_string("}")
  buf.to_string()
}

///|
fn step_result_to_parts(result : SimStepResult) -> (String, String, Int64) {
  match result {
    Ok(st) => ("ok", "", st.to_ns())
    Terminated(reason) => ("terminated", reason, 0L)
    Error(msg) => ("error", msg, 0L)
  }
}

///|
fn escape_json(s : String) -> String {
  let buf = StringBuilder::new()
  let chars = s.to_array()
  for c in chars {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Summary statistics extracted from a HilSession step log.
pub(all) struct HilSessionSummary {
  total_steps : Int
  ok_steps : Int
  error_steps : Int
  terminated : Bool
  termination_reason : String
  final_sim_time_ns : Int64
} derive(Show)

///|
pub fn hil_session_summary(session : HilSession) -> HilSessionSummary {
  let mut ok = 0
  let mut err = 0
  let mut final_time = 0L
  for step in session.step_log {
    match step {
      Ok(st) => {
        ok = ok + 1
        final_time = st.to_ns()
      }
      Terminated(_) => ok = ok + 1
      Error(_) => err = err + 1
    }
  }
  {
    total_steps: session.step_log.length(),
    ok_steps: ok,
    error_steps: err,
    terminated: session.terminated,
    termination_reason: session.termination_reason,
    final_sim_time_ns: final_time,
  }
}

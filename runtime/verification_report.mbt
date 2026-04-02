///|
/// Verification report generator (B-14).
///
/// Generates structured Markdown reports from scenario results,
/// monitor verdicts, and fault injection timelines.

///|
/// ReportEntry records a single event on the verdict timeline.
pub(all) struct ReportEntry {
  cycle : Int64
  timestamp_ns : Int64
  event_type : String
  detail : String
  verdict : Verdict
} derive(Show)

///|
/// VerificationReport collects all data needed to render a final report.
pub(all) struct VerificationReport {
  title : String
  summary_verdict : Verdict
  total_cycles : Int64
  duration_ns : Int64
  monitor_results : Array[MonitorResult]
  timeline : Array[ReportEntry]
  fault_injections : Array[String]
  metadata : Array[(String, String)]
} derive(Show)

///|
pub fn VerificationReport::new(title : String) -> VerificationReport {
  {
    title,
    summary_verdict: Pass,
    total_cycles: 0L,
    duration_ns: 0L,
    monitor_results: [],
    timeline: [],
    fault_injections: [],
    metadata: [],
  }
}

///|
/// Add a timeline entry.
pub fn VerificationReport::add_event(
  self : VerificationReport,
  cycle : Int64,
  event_type : String,
  detail : String,
  verdict : Verdict,
) -> Unit {
  self.timeline.push({ cycle, timestamp_ns: 0L, event_type, detail, verdict })
}

///|
/// Add a fault injection annotation.
pub fn VerificationReport::add_fault(
  self : VerificationReport,
  description : String,
) -> Unit {
  self.fault_injections.push(description)
}

///|
/// Add metadata key-value pair.
pub fn VerificationReport::add_meta(
  self : VerificationReport,
  key : String,
  value : String,
) -> Unit {
  self.metadata.push((key, value))
}

///|
/// Render the report as Markdown text.
pub fn VerificationReport::to_markdown(self : VerificationReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# ")
  buf.write_string(self.title)
  buf.write_string("\n\n")
  // Summary
  buf.write_string("## Summary\n\n")
  buf.write_string("| Field | Value |\n|---|---|\n")
  buf.write_string("| Verdict | ")
  buf.write_string(self.summary_verdict.to_string())
  buf.write_string(" |\n")
  buf.write_string("| Total Cycles | ")
  buf.write_string(self.total_cycles.to_string())
  buf.write_string(" |\n")
  buf.write_string("| Duration (ns) | ")
  buf.write_string(self.duration_ns.to_string())
  buf.write_string(" |\n")
  // Metadata
  for entry in self.metadata {
    buf.write_string("| ")
    buf.write_string(entry.0)
    buf.write_string(" | ")
    buf.write_string(entry.1)
    buf.write_string(" |\n")
  }
  buf.write_string("\n")
  // Monitor Results
  if self.monitor_results.length() > 0 {
    buf.write_string("## Monitor Results\n\n")
    buf.write_string("| Monitor | Verdict |\n|---|---|\n")
    for r in self.monitor_results {
      buf.write_string("| ")
      buf.write_string(r.name)
      buf.write_string(" | ")
      buf.write_string(r.verdict.to_string())
      buf.write_string(" |\n")
    }
    buf.write_string("\n")
  }
  // Fault Injections
  if self.fault_injections.length() > 0 {
    buf.write_string("## Fault Injections\n\n")
    for f in self.fault_injections {
      buf.write_string("- ")
      buf.write_string(f)
      buf.write_string("\n")
    }
    buf.write_string("\n")
  }
  // Timeline
  if self.timeline.length() > 0 {
    buf.write_string("## Verdict Timeline\n\n")
    buf.write_string(
      "| Cycle | Event | Detail | Verdict |\n|---|---|---|---|\n",
    )
    for e in self.timeline {
      buf.write_string("| ")
      buf.write_string(e.cycle.to_string())
      buf.write_string(" | ")
      buf.write_string(e.event_type)
      buf.write_string(" | ")
      buf.write_string(e.detail)
      buf.write_string(" | ")
      buf.write_string(e.verdict.to_string())
      buf.write_string(" |\n")
    }
  }
  buf.to_string()
}

///|
/// Render the report as JSON text.
pub fn VerificationReport::to_json(self : VerificationReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{")
  buf.write_string("\"title\":\"")
  buf.write_string(escape_json(self.title))
  buf.write_string("\",\"verdict\":\"")
  buf.write_string(escape_json(self.summary_verdict.to_string()))
  buf.write_string("\",\"total_cycles\":")
  buf.write_string(self.total_cycles.to_string())
  buf.write_string(",\"duration_ns\":")
  buf.write_string(self.duration_ns.to_string())
  buf.write_string(",\"monitors\":[")
  for i, r in self.monitor_results {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("{\"name\":\"")
    buf.write_string(escape_json(r.name))
    buf.write_string("\",\"verdict\":\"")
    buf.write_string(escape_json(r.verdict.to_string()))
    buf.write_string("\"}")
  }
  buf.write_string("],\"timeline\":[")
  for i, e in self.timeline {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("{\"cycle\":")
    buf.write_string(e.cycle.to_string())
    buf.write_string(",\"event\":\"")
    buf.write_string(escape_json(e.event_type))
    buf.write_string("\",\"detail\":\"")
    buf.write_string(escape_json(e.detail))
    buf.write_string("\",\"verdict\":\"")
    buf.write_string(escape_json(e.verdict.to_string()))
    buf.write_string("\"}")
  }
  buf.write_string("],\"faults\":[")
  for i, f in self.fault_injections {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("\"")
    buf.write_string(escape_json(f))
    buf.write_string("\"")
  }
  buf.write_string("]}")
  buf.to_string()
}

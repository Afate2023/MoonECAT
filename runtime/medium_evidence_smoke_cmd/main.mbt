///|
fn main {
  let report = @medium_evidence_smoke.run_medium_evidence_call_chain_smoke()
  println(
    "\{report.provider_id}|\{report.provider_kind}|\{report.section_count}|\{report.diagnostic_label}|\{report.live_claimed}",
  )
}

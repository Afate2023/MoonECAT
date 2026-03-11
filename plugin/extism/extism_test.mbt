///|
test "extism envelope encodes command and request id" {
  let req : PluginRequest = {
    version: "v1",
    command: Scan,
    request_id: "req-1",
    timeout_ns: Some(1_000_000L),
    payload: Json::object({ "interface": Json::string("eth0") }),
  }
  let encoded = encode_request(req)
  json_inspect(encoded, content={
    "version": "v1",
    "command": "scan",
    "request_id": "req-1",
    "timeout_ns": 1000000,
    "payload": { "interface": "eth0" },
  })
}

///|
test "extism scan entry returns scan payload" {
  let req : PluginRequest = {
    version: "v1",
    command: Scan,
    request_id: "req-2",
    timeout_ns: None,
    payload: Json::object({}),
  }
  let resp = scan_entry(req)
  let encoded = encode_response(resp)
  json_inspect(encoded, content={
    "version": "v1",
    "request_id": "req-2",
    "ok": true,
    "error_code": null,
    "error_message": null,
    "payload": {
      "slave_count": 0,
      "slaves": [],
    },
    "diagnostics": {
      "command": "scan",
      "backend": "mock",
    },
  })
}

///|
test "extism validate entry returns pass on mock replay" {
  let req : PluginRequest = {
    version: "v1",
    command: Validate,
    request_id: "req-3",
    timeout_ns: Some(1_000_000L),
    payload: Json::object({}),
  }
  let resp = validate_entry(req)
  let encoded = encode_response(resp)
  json_inspect(encoded, content={
    "version": "v1",
    "request_id": "req-3",
    "ok": true,
    "error_code": null,
    "error_message": null,
    "payload": {
      "total_expected": 0,
      "total_found": 0,
      "all_ok": true,
      "result_count": 0,
    },
    "diagnostics": {
      "command": "validate",
      "backend": "mock",
    },
  })
}

///|
test "extism run entry returns replay run summary" {
  let req : PluginRequest = {
    version: "v1",
    command: Run,
    request_id: "req-4",
    timeout_ns: Some(1_000_000L),
    payload: Json::object({}),
  }
  let resp = run_entry(req)
  let encoded = encode_response(resp)
  json_inspect(encoded, content={
    "version": "v1",
    "request_id": "req-4",
    "ok": true,
    "error_code": null,
    "error_message": null,
    "payload": {
      "scan": {
        "slave_count": 0,
        "slaves": [],
      },
      "validation": {
        "total_expected": 0,
        "total_found": 0,
        "all_ok": true,
        "result_count": 0,
      },
      "cycles_requested": 10,
      "cycles_ok": 10,
      "final_phase": "Done",
      "telemetry": {
        "cycles": 10,
        "tx_frames": 10,
        "rx_frames": 10,
        "timeouts": 0,
        "retries": 0,
        "wkc_errors": 0,
        "irq_events": 0,
        "dc_delay_updates": 0,
      },
    },
    "diagnostics": {
      "command": "run",
      "backend": "mock",
    },
  })
}

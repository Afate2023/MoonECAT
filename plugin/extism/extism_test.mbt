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
test "extism placeholder entry returns stable error envelope" {
  let req : PluginRequest = {
    version: "v1",
    command: Run,
    request_id: "req-2",
    timeout_ns: None,
    payload: Json::object({}),
  }
  let resp = run_entry(req)
  let encoded = encode_response(resp)
  json_inspect(encoded, content={
    "version": "v1",
    "request_id": "req-2",
    "ok": false,
    "error_code": "not_implemented",
    "error_message": "Extism run adapter is not implemented yet",
    "payload": {},
    "diagnostics": { "command": "run" },
  })
}

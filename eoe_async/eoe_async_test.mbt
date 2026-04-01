///|
test "EoeAsyncBridge new defaults" {
  let bridge = @eoe_async.EoeAsyncBridge::new()
  assert_true(bridge.is_active())
  let j = bridge.to_json()
  guard j is Json::Object(m) else {
    assert_true(false)
    return
  }
  assert_true(m.contains("active"))
  assert_true(m.contains("poll_interval_ms"))
  assert_true(m.contains("switch"))
}

///|
test "EoeAsyncBridge try_send and try_recv" {
  let bridge = @eoe_async.EoeAsyncBridge::new()
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  bridge.add_station(0x1001U, cfg)
  let data = Bytes::makei(10, fn(i) { i.to_byte() })
  assert_true(bridge.try_send(0x1001U, data))
  // try_recv should be empty (no poll cycle has run)
  assert_true(bridge.try_recv() is None)
}

///|
test "EoeAsyncBridge stop deactivates" {
  let bridge = @eoe_async.EoeAsyncBridge::new()
  assert_true(bridge.is_active())
  bridge.stop()
  assert_true(!bridge.is_active())
}

///|
test "EoeAsyncBridge switch accessor" {
  let bridge = @eoe_async.EoeAsyncBridge::new()
  let sw = bridge.switch()
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x2001U, cfg)
  let text = sw.format_text()
  assert_true(text.contains("Stations: 1"))
}

///|
async test "EoeAsyncBridge async send and recv with poll_loop" {
  let bridge = @eoe_async.EoeAsyncBridge::new(poll_interval_ms=5)
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  bridge.add_station(0x1001U, cfg)
  // Inject a completed RX frame directly into the switch
  let payload = Bytes::makei(16, fn(i) { i.to_byte() })
  let frame = @mailbox.encode_eoe_fragment(
    b'\x01', 0U, true, 0U, 0U, 0U, payload,
  )
  let _ = bridge.switch().process_received(0x1001U, frame)
  // Run poll_loop briefly in a task group with timeout
  @async.with_task_group(root => {
    root.spawn_bg(() => {
      bridge.poll_loop(@mock.MockNic::new(), @hal.Duration(10_000L))
    })
    // Give poll_loop time to run
    @async.sleep(50)
    // The frame should now be in rx_queue
    let received = bridge.try_recv()
    guard received is Some(f) else {
      assert_true(false)
      root.return_immediately(())
    }
    assert_eq(f.station, 0x1001U)
    assert_eq(f.data.length(), 16)
    bridge.stop()
  })
}

///|
async test "EoeAsyncBridge poll_loop exits when stopped" {
  let bridge = @eoe_async.EoeAsyncBridge::new(poll_interval_ms=5)
  @async.with_task_group(root => {
    let task = root.spawn(
      () => bridge.poll_loop(@mock.MockNic::new(), @hal.Duration(10_000L)),
      no_wait=true,
    )
    @async.sleep(30)
    bridge.stop()
    @async.sleep(20)
    // Task should have exited
    let result = task.try_wait()
    assert_true(result is Some(_))
  })
}

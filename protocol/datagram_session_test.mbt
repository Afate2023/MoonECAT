///|
pub struct TimeoutThenEchoNic {
  mut last_sent : Bytes
  mut recv_calls : Int
  mut is_open : Bool
}

///|
fn TimeoutThenEchoNic::new() -> TimeoutThenEchoNic {
  { last_sent: Bytes::new(0), recv_calls: 0, is_open: true }
}

///|
pub impl @hal.Nic for TimeoutThenEchoNic with fn open_(name) {
  ignore(name)
  TimeoutThenEchoNic::new()
}

///|
pub impl @hal.Nic for TimeoutThenEchoNic with fn send(self, data) {
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  self.last_sent = data
  data.length()
}

///|
pub impl @hal.Nic for TimeoutThenEchoNic with fn recv(self, timeout~) {
  ignore(timeout)
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  if self.recv_calls < 2 {
    self.recv_calls = self.recv_calls + 1
    raise @hal.EcError::RecvTimeout
  }
  self.recv_calls = self.recv_calls + 1
  self.last_sent
}

///|
pub impl @hal.Nic for TimeoutThenEchoNic with fn close(self) {
  self.is_open = false
}

///|
fn sent_datagram_indices(log : @mock.NicEventLog) -> Array[Byte] raise {
  let indices : Array[Byte] = []
  for event in log.events {
    match event {
      @mock.Sent(data, _) => {
        let frame = @protocol.EcFrame::decode(data)
        for pdu in frame.pdus {
          indices.push(pdu.header.index)
        }
      }
      _ => ()
    }
  }
  indices
}

///|
test "failed transaction consumes index and explicit retry uses the next one" {
  let recorder = @mock.RecordingNicAdapter::wrap(TimeoutThenEchoNic::new())
  let session = @protocol.DatagramSession::new(recorder)
  let pdu = @protocol.transact_pdu_retry(
    session,
    @protocol.EcCommand::NOP,
    0U,
    Bytes::new(0),
    @hal.Duration(1000L),
    1,
  )
  @debug.assert_eq(pdu.header.index, b'\x01')
  @debug.assert_eq(sent_datagram_indices(recorder.get_log()), [b'\x00', b'\x01'])
  @debug.assert_eq(session.next_index(), b'\x02')
}

///|
test "record and replay keep strict incrementing index bytes" {
  let recorder = @mock.RecordingNicAdapter::wrap(@mock.MockNic::new())
  let record_session = @protocol.DatagramSession::new(recorder)
  let timeout = @hal.Duration(1000L)
  for _ in 0..<2 {
    ignore(
      @protocol.transact_pdu(
        record_session,
        @protocol.EcCommand::NOP,
        0U,
        Bytes::new(0),
        timeout,
      ),
    )
  }
  let replay = @mock.ReplayNic::from_log(recorder.get_log())
  let replay_session = @protocol.DatagramSession::new(replay)
  for _ in 0..<2 {
    ignore(
      @protocol.transact_pdu(
        replay_session,
        @protocol.EcCommand::NOP,
        0U,
        Bytes::new(0),
        timeout,
      ),
    )
  }
  assert_true(replay.is_exhausted())
}

///|
test "legacy DatagramSession keeps fixed-zero trace compatibility" {
  let recorder = @mock.RecordingNicAdapter::wrap(@mock.MockNic::new())
  let session = @protocol.DatagramSession::legacy(recorder)
  let timeout = @hal.Duration(1000L)
  for _ in 0..<2 {
    ignore(
      @protocol.transact_pdu(
        session,
        @protocol.EcCommand::NOP,
        0U,
        Bytes::new(0),
        timeout,
      ),
    )
  }
  @debug.assert_eq(sent_datagram_indices(recorder.get_log()), [b'\x00', b'\x00'])
  @debug.assert_eq(session.next_index(), b'\x00')
}

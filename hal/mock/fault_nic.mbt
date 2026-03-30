///|
/// FaultNic wraps any Nic and injects faults according to the configured FaultInjector.
/// Composable: FaultNic(VirtualNic(...)) = virtual multi-slave bus with fault injection.
pub struct FaultNic {
  inner : VirtualNic
  injector : FaultInjector
}

///|
pub fn FaultNic::new(inner : VirtualNic, injector : FaultInjector) -> FaultNic {
  { inner, injector }
}

///|
/// Convenience: wrap a VirtualNic with a fresh injector.
pub fn FaultNic::wrap(inner : VirtualNic) -> FaultNic {
  FaultNic::new(inner, FaultInjector::new())
}

///|
pub impl @hal.Nic for FaultNic with open_(name) {
  ignore(name)
  FaultNic::wrap(VirtualNic::new(VirtualBus::new([])))
}

///|
pub impl @hal.Nic for FaultNic with send(self, data) {
  // Check for send-phase faults
  match self.injector.check_send() {
    Some(SendFailure(msg)) => raise @hal.EcError::SendFailed(msg)
    Some(_) => () // non-send faults ignored in send phase
    None => ()
  }
  // Delegate to inner NIC
  self.inner.send(data)
}

///|
pub impl @hal.Nic for FaultNic with recv(self, timeout~) {
  // Check for recv-phase faults BEFORE attempting real recv
  match self.injector.check_recv() {
    Some(RecvTimeout) => raise @hal.EcError::RecvTimeout
    Some(FrameDrop) => raise @hal.EcError::RecvTimeout
    Some(FrameCorrupt(..) as fault) => {
      let data = self.inner.recv(timeout~)
      match apply_frame_fault(fault, data) {
        Some(corrupted) => corrupted
        None => raise @hal.EcError::RecvTimeout
      }
    }
    Some(WkcCorrupt(..) as fault) => {
      let data = self.inner.recv(timeout~)
      match apply_frame_fault(fault, data) {
        Some(corrupted) => corrupted
        None => data
      }
    }
    Some(SendFailure(_)) => self.inner.recv(timeout~)
    None => self.inner.recv(timeout~)
  }
}

///|
pub impl @hal.Nic for FaultNic with close(self) {
  self.inner.close()
}

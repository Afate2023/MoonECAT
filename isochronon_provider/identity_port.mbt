///|
/// Provider-owned byte port. It deliberately exposes only transport facts;
/// EtherCAT decoding stays in the operation engine.
pub struct IdentityLinkPort {
  priv source : ProviderExecutionSource
  priv now_fn : () -> @clock.DomainInstant
  priv submit_fn : (Bytes) -> Unit raise IdentityProviderError
  priv poll_fn : (@clock.DomainInstant) -> @runtime.RxObservation? raise IdentityProviderError
  priv sleep_until_fn : (@clock.DomainInstant) -> Unit raise IdentityProviderError
}

///|
pub fn IdentityLinkPort::new(
  source~ : ProviderExecutionSource,
  now_fn~ : () -> @clock.DomainInstant,
  submit_fn~ : (Bytes) -> Unit raise IdentityProviderError,
  poll_fn~ : (@clock.DomainInstant) -> @runtime.RxObservation? raise IdentityProviderError,
  sleep_until_fn~ : (@clock.DomainInstant) -> Unit raise IdentityProviderError,
) -> IdentityLinkPort {
  { source, now_fn, submit_fn, poll_fn, sleep_until_fn }
}

///|
/// Adapt an already-open Lockwire session without changing its lifecycle.
/// Every RX call receives the operation's original absolute deadline.
pub fn IdentityLinkPort::from_link_session(
  session : @runtime.LinkSession,
  sleep_until_fn~ : (@clock.DomainInstant) -> Unit raise IdentityProviderError,
) -> IdentityLinkPort {
  IdentityLinkPort::new(
    source=RuntimeUnverified,
    now_fn=fn() { session.now() },
    submit_fn=payload => {
      let lease = session.acquire_tx(payload.length()) catch {
        error => raise TransportFailure(@debug.to_string(error))
      }
      lease.write(payload) catch {
        error => raise TransportFailure(@debug.to_string(error))
      }
      session.submit_tx(lease) catch {
        error => raise TransportFailure(@debug.to_string(error))
      }
    },
    poll_fn=deadline => {
      let pending = session.poll_rx(deadline~) catch {
        error => raise TransportFailure(@debug.to_string(error))
      }
      match pending {
        None => None
        Some(lease) => {
          let observation_result : Result[
            @runtime.RxObservation,
            IdentityProviderError,
          ] = Result::Ok(lease.observation()) catch {
            error => Result::Err(TransportFailure(@debug.to_string(error)))
          }
          let release_result : Result[Unit, IdentityProviderError] = Result::Ok(
            session.release_rx(lease),
          ) catch {
            error => Result::Err(TransportFailure(@debug.to_string(error)))
          }
          match (observation_result, release_result) {
            (Ok(observation), Ok(_)) => Some(observation)
            (Err(error), _) => raise error
            (_, Err(error)) => raise error
          }
        }
      }
    },
    sleep_until_fn~,
  )
}

///|
pub fn IdentityLinkPort::source(
  self : IdentityLinkPort,
) -> ProviderExecutionSource {
  self.source
}

///|
fn IdentityLinkPort::now(self : IdentityLinkPort) -> @clock.DomainInstant {
  (self.now_fn)()
}

///|
fn IdentityLinkPort::submit(
  self : IdentityLinkPort,
  payload : Bytes,
) -> Unit raise IdentityProviderError {
  (self.submit_fn)(provider_copy_bytes(payload))
}

///|
fn IdentityLinkPort::poll(
  self : IdentityLinkPort,
  deadline : @clock.DomainInstant,
) -> @runtime.RxObservation? raise IdentityProviderError {
  (self.poll_fn)(deadline)
}

///|
fn IdentityLinkPort::sleep_until(
  self : IdentityLinkPort,
  deadline : @clock.DomainInstant,
) -> Unit raise IdentityProviderError {
  (self.sleep_until_fn)(deadline)
}

///|
/// The first verification target rejects VLAN EtherCAT and keeps filter text
/// in the MoonECAT owner rather than ProjectDocument or generic Lockwire config.
pub fn inspect_bus_identity_capture_filter() -> @pcapng.ProviderCaptureFilterAsset raise @pcapng.PcapngError {
  @pcapng.ProviderCaptureFilterAsset::new(
    provider_id="moonecat",
    operation_id=inspect_bus_identity_operation_id,
    asset_id="moonecat.inspect-bus-identity.ethercat-non-vlan.v1",
    canonical_bpf="ether proto 0x88a4 and not vlan",
  )
}

///|
pub impl Show for RingEntry with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn RingEntry::to_string(self : RingEntry) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EventRing with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EventRing::to_string(self : EventRing) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SharedMemoryRegion with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SharedMemoryRegion::to_string(self : SharedMemoryRegion) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for BridgeConfig with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn BridgeConfig::to_string(self : BridgeConfig) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for BridgeStats with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn BridgeStats::to_string(self : BridgeStats) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for McuPlatform with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn McuPlatform::to_string(self : McuPlatform) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for McuNicConfig with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn McuNicConfig::to_string(self : McuNicConfig) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for McuNic with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn McuNic::to_string(self : McuNic) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for McuClock with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn McuClock::to_string(self : McuClock) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for McuZeroCopyNic with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn McuZeroCopyNic::to_string(self : McuZeroCopyNic) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for NativeBackendKind with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn NativeBackendKind::to_string(self : NativeBackendKind) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for NativeNicConfig with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn NativeNicConfig::to_string(self : NativeNicConfig) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for NativeInterfaceInfo with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn NativeInterfaceInfo::to_string(self : NativeInterfaceInfo) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for NativeInterfaceListing with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn NativeInterfaceListing::to_string(
  self : NativeInterfaceListing,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for NativeNic with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn NativeNic::to_string(self : NativeNic) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for QualityTrend with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn QualityTrend::to_string(self : QualityTrend) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for QualityGrade with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn QualityGrade::to_string(self : QualityGrade) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for PerfTrend with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn PerfTrend::to_string(self : PerfTrend) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for LinkGrade with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn LinkGrade::to_string(self : LinkGrade) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
/// Thin CLI adapter. ESI parsing and typed projection are owned by the
/// reusable MoonECAT device_profile package.
fn convert_esi_xml_to_json_string(
  xml_content : String,
) -> String raise @hal.EcError {
  @device_profile.convert_esi_xml_to_json_string(xml_content)
}

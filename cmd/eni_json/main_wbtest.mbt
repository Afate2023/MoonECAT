///|
test "eni-json converter projects XML into runtime ENI JSON interchange" {
  let xml =
    #|<?xml version="1.0"?>
    #|<EtherCATConfig>
    #|  <Config>
    #|    <Slave>
    #|      <Info>
    #|        <PhysAddr>1001</PhysAddr>
    #|        <Identification Value="0x20" />
    #|        <VendorId>2</VendorId>
    #|        <ProductCode>#x04D2</ProductCode>
    #|        <RevisionNo>1</RevisionNo>
    #|        <SerialNo>4660</SerialNo>
    #|      </Info>
    #|      <ProcessData>
    #|        <Sm No="2" />
    #|        <Sm No="3" />
    #|        <RxPdo Fixed="1" />
    #|        <TxPdo Fixed="1" />
    #|      </ProcessData>
    #|      <Fmmu>Outputs</Fmmu>
    #|      <Fmmu>Inputs</Fmmu>
    #|      <Mailbox>
    #|        <CoE />
    #|        <FoE />
    #|      </Mailbox>
    #|      <Dc>
    #|        <OpMode>
    #|          <AssignActivate>0x300</AssignActivate>
    #|        </OpMode>
    #|      </Dc>
    #|    </Slave>
    #|  </Config>
    #|</EtherCATConfig>
  let json_text = convert_eni_xml_to_json_string(xml)
  let model = @runtime.configuration_from_eni_json(json_text)
  assert_eq(model.source, @runtime.EniImport)
  assert_eq(model.total_slaves, 1)
  assert_eq(model.slaves[0].configured_address, Some(1001U))
  assert_eq(model.slaves[0].identification, Some(0x20U))
  assert_eq(
    model.slaves[0].identity,
    Some({ vendor_id: 2U, product_code: 0x04D2U, revision: 1U, serial: 4660U }),
  )
  assert_eq(
    model.slaves[0].process_data_summary,
    Some({
      sync_manager_count: 2,
      fmmu_count: 2,
      rx_pdo_count: 1,
      tx_pdo_count: 1,
      mailbox_protocols: Some({
        aoe: false,
        coe: true,
        eoe: false,
        foe: true,
        soe: false,
        voe: false,
      }),
      dc_op_mode_count: 1,
      dc_assign_activate_count: 1,
    }),
  )
}

///|
test "eni-json converter rejects invalid XML numeric fields" {
  let xml =
    #|<?xml version="1.0"?>
    #|<EtherCATConfig>
    #|  <Config>
    #|    <Slave>
    #|      <Info>
    #|        <PhysAddr>bad-address</PhysAddr>
    #|      </Info>
    #|    </Slave>
    #|  </Config>
    #|</EtherCATConfig>
  let result : Result[String, Error] = try? convert_eni_xml_to_json_string(xml)
  guard result is Err(@hal.EcError::EsiParseFailed(message)) else {
    fail("expected invalid ENI numeric field to raise EsiParseFailed")
  }
  assert_true(
    message.contains("invalid numeric ENI field at Slave/Info/PhysAddr"),
  )
}

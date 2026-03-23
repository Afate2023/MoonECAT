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

///|
test "eni-json converter projects ESI XML into shared ESI JSON interchange" {
  let xml =
    #|<?xml version="1.0"?>
    #|<EtherCATInfo>
    #|  <Vendor><Id>#x0001</Id></Vendor>
    #|  <Descriptions>
    #|    <Devices>
    #|      <Device Physics="YY">
    #|        <Type ProductCode="#x00000002" RevisionNo="#x00000003">demo</Type>
    #|        <Name>demo</Name>
    #|        <Profile><ProfileNo>402</ProfileNo></Profile>
    #|        <Fmmu>Outputs</Fmmu>
    #|        <Sm DefaultSize="64" StartAddress="#x1000" ControlByte="#x26" Enable="1">MBoxOut</Sm>
    #|        <Sm DefaultSize="64" StartAddress="#x1400" ControlByte="#x22" Enable="1">MBoxIn</Sm>
    #|        <Mailbox><CoE SdoInfo="1"><InitCmd><Transition>SO</Transition><Index>#x6060</Index><SubIndex>0</SubIndex><Data>08</Data></InitCmd></CoE></Mailbox>
    #|        <Dc><OpMode><Name>DC</Name><Desc>Demo</Desc><AssignActivate>#x0300</AssignActivate></OpMode></Dc>
    #|        <Slots SlotIndexIncrement="#x800" SlotPdoIncrement="16"><Slot><ModuleIdent Default="1">#x00000010</ModuleIdent></Slot></Slots>
    #|        <Eeprom><ByteSize>512</ByteSize><ConfigData>0100020003000400</ConfigData><BootStrap>0010200020102000</BootStrap></Eeprom>
    #|      </Device>
    #|    </Devices>
    #|    <Modules>
    #|      <Module>
    #|        <Type ModuleIdent="#x00000010">demo-module</Type>
    #|        <RxPdo Sm="2"><Index>#x1600</Index><Name>Outputs</Name><Entry><Index>#x7000</Index><SubIndex>1</SubIndex><BitLen>16</BitLen><Name>Out</Name><DataType>UINT</DataType></Entry></RxPdo>
    #|      </Module>
    #|    </Modules>
    #|  </Descriptions>
    #|</EtherCATInfo>
  let json_text = convert_esi_xml_to_json_string(xml)
  let document = @runtime.parse_esi_json_document(json_text)
  assert_eq(document.devices.length(), 1)
  assert_eq(document.devices[0].vendor_id, 1U)
  assert_eq(document.devices[0].product_code, 2U)
  assert_eq(document.devices[0].profile_no, Some(402U))
  assert_eq(document.devices[0].init_commands.length(), 1)
  assert_eq(document.devices[0].mailbox.coe_present, true)
  let report = @runtime.offline_sii_report_from_esi_json(json_text, 0)
  assert_eq(report.header.vendor_id, 1U)
  assert_eq(report.header.product_code, 2U)
  guard report.general is Some(general) else {
    fail("expected offline sii general section")
  }
  assert_eq(general.ds402_channels, b'\x01')
  assert_eq(report.startup_mailbox_commands.length(), 1)
  assert_eq(report.categories.length() > 0, true)
}

///|
test "eni-json converter preserves device-level pdos for offline sii projection" {
  let xml =
    #|<?xml version="1.0"?>
    #|<EtherCATInfo>
    #|  <Vendor><Id>#x0001</Id></Vendor>
    #|  <Descriptions>
    #|    <Devices>
    #|      <Device Physics="YY">
    #|        <Type ProductCode="#x00000002" RevisionNo="#x00000003">demo</Type>
    #|        <Name>demo</Name>
    #|        <Profile><ProfileNo>402</ProfileNo></Profile>
    #|        <Fmmu>Outputs</Fmmu>
    #|        <Fmmu>Inputs</Fmmu>
    #|        <Sm DefaultSize="64" StartAddress="#x1000" ControlByte="#x26" Enable="1">MBoxOut</Sm>
    #|        <Sm DefaultSize="64" StartAddress="#x1400" ControlByte="#x22" Enable="1">MBoxIn</Sm>
    #|        <Sm DefaultSize="0" StartAddress="#x1100" ControlByte="#x64" Enable="1">Outputs</Sm>
    #|        <Sm DefaultSize="0" StartAddress="#x1200" ControlByte="#x20" Enable="1">Inputs</Sm>
    #|        <RxPdo Sm="2"><Index>#x1600</Index><Name>Outputs</Name><Entry><Index>#x6040</Index><SubIndex>0</SubIndex><BitLen>16</BitLen><Name>ControlWord</Name><DataType>UINT</DataType></Entry></RxPdo>
    #|        <TxPdo Sm="3"><Index>#x1A00</Index><Name>Inputs</Name><Entry><Index>#x6041</Index><SubIndex>0</SubIndex><BitLen>16</BitLen><Name>StatusWord</Name><DataType>UINT</DataType></Entry></TxPdo>
    #|        <Mailbox><CoE SdoInfo="1"><InitCmd><Transition>SO</Transition><Index>#x6060</Index><SubIndex>0</SubIndex><Data>08</Data></InitCmd></CoE></Mailbox>
    #|      </Device>
    #|    </Devices>
    #|  </Descriptions>
    #|</EtherCATInfo>
  let json_text = convert_esi_xml_to_json_string(xml)
  let document = @runtime.parse_esi_json_document(json_text)
  assert_eq(document.devices[0].rx_pdos.length(), 1)
  assert_eq(document.devices[0].tx_pdos.length(), 1)
  let report = @runtime.offline_sii_report_from_esi_json(json_text, 0)
  assert_eq(report.rx_pdo.length(), 1)
  assert_eq(report.tx_pdo.length(), 1)
  assert_eq(report.rx_pdo[0].pdo_index, 0x1600U)
  assert_eq(report.tx_pdo[0].pdo_index, 0x1A00U)
  guard report.general is Some(general) else {
    fail("expected offline sii general section")
  }
  assert_eq(general.ds402_channels, b'\x01')
  assert_eq(report.startup_mailbox_commands.length(), 1)
  assert_eq(report.startup_mailbox_commands[0].index, 0x6060U)
}

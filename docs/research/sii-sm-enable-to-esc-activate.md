# SII SyncManager Enable vs. ESC Activate

## Conclusion

The eight-byte SII SyncM category entry is not an eight-byte ESC SyncManager
register image. In particular, SII offsets 6 and 7 are category metadata and
must not be copied verbatim to ESC register offsets 6 and 7.

When MoonECAT materializes an `SmConfig`, only bit 0 of the SII Enable Sync
Manager byte maps to ESC `Activate.ChannelEnable`. SII bits 1-3 describe fixed
content, virtual, and OP-only behavior; they are not ESC Activate bits.

## Normative evidence

- `References/ETG2010_S_R_V1i0i2_EtherCATSIISpecification/hybrid_auto/ETG2010_S_R_V1i0i2_EtherCATSIISpecification.md`
  defines SyncM offset 6 as Enable Sync Manager metadata and offset 7 as Sync
  Manager Type. It explicitly says these two bytes cannot be used as the
  corresponding ESC register contents.
- `References/ETG1000_4_CHN_EcatDLLServices_V1i0i2_C01/ETG1000_4_CHN_EcatDLLServices_V1i0i2_C01.md`
  defines ESC SM offset 6 as Activate (`ChannelEnable`, `Repeat`, DC event bits)
  and offset 7 as PDI Control. These fields have different semantics from the
  SII category metadata.

## Reference implementations

- EtherCrab models the SII Enable byte as metadata and maps only its `ENABLE`
  bit into the ESC SyncManager channel enable field.
- gatorcat likewise decodes a distinct SII enable structure and constructs a
  fresh ESC SM register image, mapping only `enable` to
  `activate.channel_enable` while clearing repeat, DC, and PDI control fields.

## MoonECAT finding and implementation boundary

`mailbox/calculate_sm_configs` previously copied `SiiSmEntry.activate`
verbatim into `SmConfig.activate`. Values such as `0x0F` therefore programmed
reserved/Repeat-related ESC bits even though the SII value only meant enabled,
fixed, virtual, and OP-only.

The compatibility-preserving fix keeps the public legacy field name but adds
an explicit conversion boundary: `SmConfig.activate = sii_flags & 0x01`.
`SmConfig::to_bytes` remains an ESC-register serializer and writes PDI Control
as zero; it does not serialize SmType into byte 7.

## Regression case

- SII Enable byte `0x0F` must produce ESC Activate byte `0x01`.
- SII Enable byte `0x0E` must produce ESC Activate byte `0x00`.

The fixed/virtual/opOnly policies remain metadata-policy concerns and are not
implicitly implemented by setting ESC Activate bits.

# MCU protocol notes

These notes apply to the stock 68.00.09 application only. They combine passive UART observation and disassembly of the device owner's own executable. The vendor executable and private captures are not redistributed.

## Transport

The stock application opens `/dev/ttySAK1`. Frames observed so far use `FF FF`, a command byte, a payload-length byte, then the payload. Some acknowledgements use `FF FC`. There is no universal frame checksum; the schedule command includes its own payload checksum.

## Schedules

- Query: `FF FF 30 03 01 00 01` (observed on hardware).
- Query response payload: `01 <count> <rows> <checksum>` (observed on hardware).
- Set payload: `10 <count> <rows> <checksum>` (inferred from the stock encoder; hardware write/readback validation pending).
- Each row has five bytes: weekday mask, hour, minute, portions, enabled.
- Weekday bits: Sunday bit 0 through Saturday bit 6.
- Enabled: 0 disabled, 1 enabled. The stock DP207 parser converts character 8 of each 15-character row into this field.
- Checksum: sum of all preceding payload bytes modulo 256.
- The stock application allocates space for eight rows.

The first captured schedule table contained disabled entries. Reading a stored table does not prove that enabled meals execute correctly without the camera CPU or batteries.

## Manual feeding

The stock DP201 handler at `0x17e54` calls the encoder at `0x14b0a8`. It generates command `01` with a ten-byte payload:

```text
3A 09 03 0E 0B <grams-low> <grams-high> 00 00 00
```

The application multiplies the requested portions by a fixed ten-gram value. This differs from short manual-feed frames documented for other feeder variants. Hardware comparison and a single bounded test are required before enabling this encoder in a control API.

## Required write guarantees

The local API must validate counts and ranges, reject stale schedule revisions, issue a write once, and verify the MCU's fresh readback. A timeout must not turn into repeated feeding. Changing a UI portion selector must never emit a motor command.

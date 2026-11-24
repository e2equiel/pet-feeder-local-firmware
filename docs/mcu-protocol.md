# MCU protocol notes

These notes apply to the stock 68.00.09 application only. They combine passive UART observation and disassembly of the device owner's own executable. The vendor executable and private captures are not redistributed.

## Transport

The stock application opens `/dev/ttySAK1`. Frames observed so far use `FF FF`, a command byte, a payload-length byte, then the payload. Some acknowledgements use `FF FC`. There is no universal frame checksum; the schedule command includes its own payload checksum.

## Schedules

- Query: `FF FF 30 03 01 00 01` (observed on hardware).
- Query response payload: `01 <count> <rows> <checksum>` (observed on hardware).
- Set payload: `10 <count> <rows> <checksum>` (verified by writing, querying, and restoring a disabled hardware fixture with Internet blocked).
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

The application multiplies the requested portions by a fixed ten-gram value. This differs from short manual-feed frames documented for other feeder variants. A single one-portion stock command was captured on hardware and matched this encoder byte for byte. The MCU acknowledged command `01` with payload `00`. Further completion/status reports still require decoding; an acknowledgement does not prove that food was dispensed.

## Hardware validation so far

- Reading the original schedule table.
- Writing the identical disabled table and verifying a fresh MCU readback.
- Adding one disabled synthetic entry, reading the changed table, restoring the original table, and verifying exact readback, all while Internet routes were blocked.
- Comparing one stock one-portion command against the reconstructed encoder.

One one-portion command was subsequently sent through the authenticated local API and acknowledged. Repeating its operation ID did not send another command. A scheduled-feeding record was also captured from the MCU with the entire camera application stopped for 25 seconds; the API manual-command counter did not increase. Physical delivery and battery-backed operation remain unverified.

## MCU wall clock

Stock function `0x14b394` emits command `06`, payload length six: `(full year + 0x58) modulo 256`, month, day, hour, minute, second. This encoding matched captured stock frames and the new API received an MCU acknowledgement when sending current local wall time. The month and day are one-based; there is no universal checksum on this frame. Acknowledgement is not independent clock readback.

## Required write guarantees

The local API must validate counts and ranges, reject stale schedule revisions, issue a write once, and verify the MCU's fresh readback. A timeout must not turn into repeated feeding. Changing a UI portion selector must never emit a motor command.

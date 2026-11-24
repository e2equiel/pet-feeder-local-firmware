# Local API, version 1

HTTP listens on port 8080. Every API request requires `Authorization: Bearer <device-token>`. Generate a random token of at least 32 ASCII alphanumeric, hyphen, or underscore characters, and store it in `PF_STATE_DIR/api.token`. The default state directory is `/mnt/config/pet-feeder-local`; RAM experiments override it. Tokens and state files are private device data.

| Method | Path | Behavior |
| --- | --- | --- |
| GET | `/api/v1/info` | Device identity, API version, model, and capabilities |
| GET | `/api/v1/status` | Observed MCU connectivity, serial faults, clock sync, and command counter |
| GET | `/api/v1/schedules` | Query the MCU and return its fresh table and revision |
| PUT | `/api/v1/schedules` | Validate, compare a fresh revision, write once, query again, and verify exact readback |
| POST | `/api/v1/clock` | Send explicit local year/month/day/hour/minute/second and await MCU acknowledgement |
| POST | `/api/v1/feed` | Reserve an operation ID durably before sending one motor command |

Schedule writes contain `expected_revision` and `meals`. Each meal has `weekdays` (Sunday bit 0 through Saturday bit 6), `hour`, `minute`, `portions` (1–10), and boolean `enabled`. The MCU supports at most eight rows. A stale revision returns HTTP 409. A successful update returns `verified: true` only after a matching fresh query response. Missing acknowledgement or mismatched readback is an error, not success.

Feeding requires `feeding.enabled` in the state directory. The JSON body contains `portions` and an ASCII `operation_id` of at most 64 alphanumeric, hyphen, or underscore characters. A successful response contains the same ID and `accepted: true`. `dispensed: null` deliberately makes no claim about physical delivery. Motor completion/error codes remain only partially understood.

The journal atomically replaces a bounded file and synchronizes the file and directory before issuing a motor command. A reserved ID with an unknown outcome is never resent while it remains in the sixteen-entry journal. Duplicate acknowledged IDs return the saved acknowledgement. Reusing an ID for another portion count is rejected. This is bounded replay protection, **not a claim of exactly-once physical delivery across every possible power failure**. Clients must never blindly retry uncertain feeding requests. A partial serial write disables further writes in that process.

Clock fields are wall time in the household's configured timezone, not UTC epoch seconds. Home Assistant periodically synchronizes them while online. A scheduled-feeding serial record was captured with the entire camera process stopped for 25 seconds and no API motor commands. Physical delivery, battery retention, and behavior after complete power loss still require hardware validation. The vendor process's full-frame clock, motor, and schedule-update writes are filtered so that its cloud state does not own those controls.

RTSP uses TCP interleaving and HEVC: main video is port 8555, substream is port 8556. The username is `feeder`; the password is the same private token. Authentication is Basic over the LAN. Audio is not implemented. Each stream accepts one consumer; use go2rtc to share it with Home Assistant and Frigate. Main video has been validated; the substream still needs separate validation.

Build with `make test` and `make rtsp` using an ARMv5TE GNU cross compiler. The preload must have both SysV and GNU hash tables. Before loading it, run `tools/check_imports.py` against a privately extracted original libc and perform an eager-loader check on the device. Vendor libraries are not distributed in this repository.

The persistent launcher discards vendor application output instead of accumulating an unbounded RAM log while the cloud SDK retries offline connections. The small boot-validation log stays in RAM. `scripts/uninstall.sh` disables this overlay and its boot hook, restores the original executable path and routing, and retains the private token/journal for recovery.

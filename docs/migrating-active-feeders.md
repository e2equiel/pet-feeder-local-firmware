# Migrating feeders that already serve meals

Migrate **one feeder at a time**. Keep the other feeder running its original schedule until the first has passed a real scheduled meal. Use the [complete native installer release](https://github.com/e2equiel/pet-feeder-local-firmware/releases), then HA integration **0.4.1 or later**. No new overlay payload is needed for the 0.4 weekday correction.

## Prepare before installing

1. Identify the physical feeder, its current LAN address and its existing HA entry. Do not identify a device by sending food commands. The installer must confirm the supported application fingerprint and flash layout; matching appearance or a Tuya product name is insufficient.
2. Record the current schedule **separately for each feeder**: all rows, weekdays, local time, portions and enabled flags. Include disabled rows. Up to eight rows are supported. Compare any cached HA/cloud export with the current Tuya/Smart Life screen before relying on it; cached data is not a fresh MCU read.
3. Choose a window outside a scheduled meal, with stable power and the computer remaining on the same LAN. Allow time for both complete backups, activation and verification. Save each feeder's backups in its own private folder.
4. Check the observation camera and which physical bowls it can see. Also prepare the feeder's own camera, preferably through a shared restream. An available camera entity does not establish that fresh frames arrive or that food is visible.
5. Review automations referring to the old entities, especially manual serving and camera night vision. Do not disable a shared Tuya integration or replace an entire shared camera configuration. The local integration currently provides feeding, schedule, camera and MCU connectivity controls; it does not expose every legacy camera setting or food-empty/blockage sensor. Confirm the retained camera's local automatic night vision before migration if needed.

## Install and compare the schedule

Use the installer's normal check, review, private backups and install flow for this single address. Do not bypass a fingerprint or backup mismatch. Retain the old HA entry and its configuration for recovery; when switching controls, disable only that feeder's legacy entry rather than deleting history.

The installer does not send a feeding command or replace the MCU schedule. On an **existing overlay upgrade**, it also compares the previous API table with the new readback and rolls back on a mismatch. A **first installation** has no prior local API table to compare. Its successful completion is therefore not proof that a recorded active schedule matches: compare the new MCU readback against the recorded baseline yourself before editing anything.

Confirm every row, not just the total count. Eight enabled rows can still have a wrong day or portion count. HA 0.4+ uses Sunday bit 0 for its sensor/action/calendar; the supported raw API v1 uses Saturday bit 0. The HA client performs this conversion. Daily and Monday–Friday masks are symmetric and unchanged. Do not apply a second reversal to HA actions.

Connect this device to HA with its new private token, confirm the household timezone, and verify clock synchronization and MCU availability. Do not copy a sample schedule or another feeder's schedule onto an active feeder as an installation check.

## Observe delivery and local video

Use one upstream go2rtc connection per feeder, shared by HA and Frigate. Replace only the selected stream source and preserve the camera name, recording settings and other streams. Check fresh frames in each view. Keep the overhead view for confirming that food actually reaches the intended bowl.

Observe one deliberate manual portion and the **next normal saved meal**, keeping manual requests separate from the schedule. A full eight-row table has no spare ninth row: observe the existing meal rather than appending a test row or leaving a duplicate meal enabled. A motor sound or serial acknowledgement alone is not proof of food delivery.

For the scheduled observation, the overlay already blocks the feeder's Internet routes. Temporarily disable only its new HA entry before the meal, leaving the independent go2rtc/Frigate viewers running, then restore the entry afterward. Record the observation window and verify that no API manual-feed command was added. HA Core does not need to be stopped. The separate test-unit experiments already paused the entire Linux control application; repeating that method also interrupts its camera and needs the independent overhead view.

If a meal fails, the table differs or a result is uncertain, stop the migration before moving to the next feeder. Do not blindly repeat a Serve request or overwrite a different live table. Inspect the evidence and use the installer's documented stock restoration if required. Firmware/configuration rollback and recovery of a changed MCU table are separate concerns; keep the schedule baseline.

Only after both individual devices pass should they be selected together in the HA card. Switching feeders preserves separate drafts. Schedule copy replaces the destination's entire table, including enabled flags; use it only when you intend those feeders to share the displayed schedule.

Battery and complete-power-loss testing may be deferred when outside the household's intended setup, for example with UPS-backed power. This does not establish battery behavior, clock retention after total power loss, or UPS runtime. Recheck after an actual prolonged outage.

## Optional offline comparison for advanced users

The installer itself remains a native app without Python. Developers/operators who already have Python 3.10+ can use [`tools/audit_schedule.py`](../tools/audit_schedule.py) from this repository to compare two private snapshots **without any network request or device command**:

```sh
python3 tools/audit_schedule.py --before before-private.json --after after-private.json
```

Both files explicitly identify the same physical device and declare their weekday convention. Example with synthetic data:

```json
{
  "format": 1,
  "device_id": "THE_SAME_VERIFIED_DEVICE_ID_IN_BOTH_FILES",
  "weekday_order": "sunday_bit_0",
  "meals": [
    {"weekdays": 4, "hour": 12, "minute": 30, "portions": 1, "enabled": false}
  ]
}
```

For raw API data, use `saturday_bit_0` and the raw `meals` response. Never infer identity from matching meal times or give both devices the same placeholder ID. Keep snapshots private. The report omits device identities and meal times, lists changed row numbers, and returns exit code 0 for an exact match, 1 for changed rows and 2 for an invalid or mismatched-device input. It neither imports a schedule nor triggers feeding. Comparing two copied files is not independent evidence that the MCU stored them.

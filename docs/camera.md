# Local camera with Home Assistant and Frigate

The main source is `rtsp://feeder:YOUR_PRIVATE_TOKEN@FEEDER_IP:8555/live`. Use TCP. The source is HEVC at 1920×1080 / 10 fps; it has no audio. Keep this URL private because it includes the API token.

For HA alone, leave the integration's optional restream field empty. HA uses one stream worker for both still images and live video. Browser/device HEVC support varies. If your browser cannot play it, use a local H.264 transcode provided by your own go2rtc/FFmpeg setup.

For HA and Frigate together, let **one** go2rtc instance read the feeder, then point both consumers at that instance. Frigate already includes go2rtc. Merge the following example into your own configuration rather than replacing unrelated cameras:

```yaml
go2rtc:
  streams:
    local_feeder:
      - rtsp://feeder:YOUR_PRIVATE_TOKEN@FEEDER_IP:8555/live

cameras:
  local_feeder:
    ffmpeg:
      inputs:
        - path: rtsp://127.0.0.1:8554/local_feeder
          input_args: preset-rtsp-restream
          roles: [detect, record]
    detect:
      width: 1920
      height: 1080
      fps: 5
```

In HA, enter `rtsp://FRIGATE_IP:8554/local_feeder` as the optional shared stream URL. Keep your own recording policy, object detection settings and authentication/network restrictions. This example defines an input; it does not turn on every recording option.

The feeder accepts one reader per native stream; opening a second direct viewer replaces the first. Port 8556 exists experimentally but has not been validated separately. The installer exposes only the tested main-stream route in its setup details.

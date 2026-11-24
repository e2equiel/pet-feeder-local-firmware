# Debian 12 preserves the 32-bit libc ABI expected by the supported feeder.
# Newer Ubuntu cross headers redirect calls to time64/fortified symbols absent
# from this device's uClibc. Keep the import gate enabled on every release.
FROM debian:bookworm-slim@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc-arm-linux-gnueabi libc6-dev-armel-cross make \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src

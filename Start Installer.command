#!/bin/sh
# Source launcher: use an already installed Python, not a bundled Mach-O runtime.
set -eu
cd "$(dirname "$0")"
for interpreter in /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    if test -x "$interpreter" && "$interpreter" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))' 2>/dev/null; then
        exec "$interpreter" install.py "$@"
    fi
done
printf '%s\n' 'Python 3.10 or newer was not found.' 'Install Python from https://www.python.org/downloads/macos/ and open this launcher again.'
printf '%s' 'Press Return to close this window. '
read -r answer

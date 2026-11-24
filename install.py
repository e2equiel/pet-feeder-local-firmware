#!/usr/bin/env python3
"""Launch the local installer; GUI package checks write startup failures to JSON."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / "installer"))


def launch() -> None:
    # A windowed macOS build has no stderr. The disconnected archive test needs
    # a deterministic error result instead of a hidden crash dialog.
    ready = None
    if "--demo" in sys.argv and "--no-browser" in sys.argv and "--ready-file" in sys.argv:
        index = sys.argv.index("--ready-file")
        if index + 1 < len(sys.argv):
            ready = Path(sys.argv[index + 1])
    try:
        from pet_feeder_installer.wizard import main
        main()
    except Exception as error:
        if ready is not None:
            import json
            import traceback
            ready.write_text(json.dumps({"error": type(error).__name__, "traceback": traceback.format_exc()}))
            raise SystemExit(1) from None
        raise


if __name__ == "__main__":
    launch()

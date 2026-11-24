#!/usr/bin/env python3
"""Launch the bundled local installer (Python 3.10 or newer)."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent / "installer"))
from pet_feeder_installer.wizard import main
if __name__ == "__main__":
    main()

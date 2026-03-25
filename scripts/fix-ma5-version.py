#!/usr/bin/env python3
"""Fix version.txt.

See: https://github.com/MadAnalysis/madanalysis5/issues/311#issuecomment-4116142026
This issue may be resolved in a future MG5 or MA5 update.
Unlike applying a patch, running this script will never conflict with such an update.

Usage: fix-ma5-version.py <MA5_DIR>

"""

import re
import subprocess
import sys
from pathlib import Path

ma5_dir = Path(sys.argv[1])

s = subprocess.run(  # noqa: S603
    [ma5_dir / "bin" / "ma5", "--version"],
    stdout=subprocess.PIPE,
    check=True,
    text=True,
).stdout

# Strip ANSI color codes.
s = re.sub(r"\x1b\[[0-9;]*m", "", s)

# Version example: "MA5: MA5 release : 1.11.0 [ 2025/04/23 ]"
m = re.search(r"MA5\s+release\s*:\s*(\S+)\s*\[\s*(\S+)\s*\]", s)

if not m:
    msg = f"Unexpected output from 'ma5 --version': {s}"
    raise ValueError(msg)

with (ma5_dir / "version.txt").open("w") as f:
    print(f"MA5 version {m.group(1)}", file=f)
    print(f"Date {m.group(2)}", file=f)

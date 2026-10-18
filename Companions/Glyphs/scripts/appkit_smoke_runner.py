# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Keep native initialization failures observable without aborting the runner."""
import signal
import subprocess
import sys


def run_native(script, arguments=()):
    command=[sys.executable,'-u','-X','faulthandler',str(script),'--native-worker',*arguments]
    try:
        completed=subprocess.run(command,timeout=120,check=False)
    except subprocess.TimeoutExpired:
        print('FAIL: AppKit smoke worker timed out after 120 seconds.',file=sys.stderr)
        return 1
    if completed.returncode<0:
        name=signal.Signals(-completed.returncode).name
        print('FAIL: AppKit smoke worker terminated with %s. No native pass was recorded.'%name,file=sys.stderr)
        if completed.returncode==-signal.SIGABRT:
            print('If the trace ends in NSApplication initialization / _RegisterApplication, '
                  'run this isolated check from an authorized macOS GUI session with WindowServer '
                  'and application-registration access. A restricted shell sandbox can abort '
                  'before panel construction; do not weaken the plugin or count that as a pass.',file=sys.stderr)
        return 1
    return completed.returncode

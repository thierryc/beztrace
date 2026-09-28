# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Main-thread session state; worker results are accepted by generation only."""
import threading
from .contract import CompanionError


class Session:
    def __init__(self):
        self.generation = 0
        self.cancel = threading.Event()
        self.result = None
        self.has_traced = False
        self.target = None
        self.busy = False
        self.applied = False
        self.closed = False
        self.poisoned = False

    def invalidate(self):
        self.cancel.set()
        self.generation += 1
        self.result = None
        self.busy = False

    def begin(self, target):
        if self.closed or self.poisoned:
            raise CompanionError('Open a new trace window before continuing')
        self.invalidate()
        self.cancel = threading.Event()
        self.target = target
        self.applied = False
        self.busy = True
        return self.generation, self.cancel

    def complete(self, generation, result):
        if self.closed or generation != self.generation or self.cancel.is_set():
            return False
        self.busy = False
        self.result = result
        self.has_traced = True
        return True

    def can_apply(self):
        return bool(self.result and self.target and not (self.busy or self.applied or self.closed or self.poisoned))

    def mark_applied(self):
        if not self.can_apply():
            raise CompanionError('Trace and review the current target before applying')
        self.applied = True

    def close(self):
        self.invalidate()
        self.closed = True

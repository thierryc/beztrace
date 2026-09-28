# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Small pure policies shared by native UI and unit tests."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Actions:
    trace_enabled: bool
    apply_enabled: bool
    cancel_visible: bool
    primary: str
    trace_title: str


def actions(session, has_image, has_preview):
    ready = not (session.closed or session.poisoned)
    apply = bool(ready and session.can_apply() and has_preview)
    trace = bool(ready and has_image and session.target and not session.busy)
    return Actions(trace, apply, bool(session.busy), 'apply' if apply else 'trace',
                   'Retrace' if session.has_traced else 'Trace')


def mode_after_edit(mode, field):
    return 'Custom' if field in ('height', 'bottom') else mode


def accepts_image(path):
    return path.suffix.lower() in ('.png', '.jpg', '.jpeg')

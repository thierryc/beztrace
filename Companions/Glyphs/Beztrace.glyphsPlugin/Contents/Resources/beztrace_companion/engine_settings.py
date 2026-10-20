# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Persistent engine selection. This module never installs or changes an engine."""
import json
import os
from pathlib import Path
import stat
import tempfile

from .contract import CompanionError

MAX_SETTINGS_BYTES = 16384


def settings_path(home=None):
    return Path(home if home is not None else Path.home()) / 'Library/Application Support/beztrace/engine-settings-v1.json'


def _check_parents(path):
    for parent in path.parents:
        if parent.is_symlink() and str(parent) not in ('/tmp', '/var'):
            raise CompanionError('Engine settings parent must not be a symbolic link')


def _read(path):
    _check_parents(path)
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None
    except OSError as exc:
        raise CompanionError('Cannot safely read engine settings: ' + str(exc)) from exc
    with os.fdopen(descriptor, 'rb') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise CompanionError('Engine settings must be a regular file')
        content = stream.read(MAX_SETTINGS_BYTES + 1)
    if len(content) > MAX_SETTINGS_BYTES:
        raise CompanionError('Engine settings exceed 16 KiB')
    return content


def _decode(content):
    if content is None:
        return {'schemaVersion': 1}
    try:
        value = json.loads(content)
    except (ValueError, UnicodeError, RecursionError) as exc:
        raise CompanionError('Invalid engine settings JSON') from exc
    if not isinstance(value, dict) or type(value.get('schemaVersion')) is not int or value['schemaVersion'] != 1:
        raise CompanionError('Unsupported engine settings schema')
    for key in ('userEngine', 'managedEngine'):
        if key in value:
            path = value[key]
            if not isinstance(path, str) or not Path(path).is_absolute() or '\0' in path:
                raise CompanionError(key + ' must name an absolute engine path')
    return value


def selected_engine(fallback, home=None):
    settings = _decode(_read(settings_path(home)))
    # A stale explicit choice must fail at launch, never silently switch engines.
    return settings.get('userEngine', settings.get('managedEngine', fallback))


def save_user_engine(executable, home=None):
    if not isinstance(executable, str) or not Path(executable).is_absolute() or '\0' in executable:
        raise CompanionError('Choose an absolute engine executable path')
    if not Path(executable).is_file() or not os.access(executable, os.X_OK):
        raise CompanionError('Choose an existing engine executable')
    path = settings_path(home)
    original = _read(path)
    settings = _decode(original)
    settings['userEngine'] = executable
    content = (json.dumps(settings, sort_keys=True, indent=2) + '\n').encode('utf-8')
    if len(content) > MAX_SETTINGS_BYTES:
        raise CompanionError('Engine settings exceed 16 KiB')
    path.parent.mkdir(parents=True, exist_ok=True)
    _check_parents(path)
    descriptor, temporary = tempfile.mkstemp(prefix='.engine-settings-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        if _read(path) != original:
            raise CompanionError('Engine settings changed; choose the engine again')
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)

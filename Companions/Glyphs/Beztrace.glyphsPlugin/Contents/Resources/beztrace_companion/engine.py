# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Bounded, cancellable subprocess transport. Never imports AppKit or Glyphs."""
import os
import json
import selectors
import signal
import subprocess
import threading
import time
from pathlib import Path
from .contract import CompanionError, ENGINE_VERSIONS, MAX_INPUT, MAX_OUTPUT, parse_result, number

DEFAULT_ENGINE = '/Library/Application Support/beztrace/bin/beztrace'
DEFAULT_OPTIONS = dict(threshold='auto', invert=False, accuracy=2.0, smoothing=1.0,
                       corner_threshold=12.0, min_contour_area=100.0, grid=2,
                       structure_grid=0, refine_raster=True, rtl_start=False)
EXIT_ERRORS = {2: 'Invalid tracing settings', 3: 'Image is unreadable, unsupported, or too large',
               4: 'Image contains no traceable outlines', 5: 'Tracing or geometry validation failed',
               6: 'Engine could not serialize its result', 7: 'Engine internal error'}


class Cancelled(CompanionError):
    pass


def arguments(options):
    values = dict(DEFAULT_OPTIONS)
    if set(options) - set(values):
        raise CompanionError('Unsupported tracing option')
    values.update(options)
    args = ['trace', '-', '--format', 'json', '--json-errors']
    threshold = values['threshold']
    if threshold != 'auto' and not (type(threshold) is int and 0 <= threshold <= 255):
        raise CompanionError('Threshold must be auto or an integer from 0 to 255')
    args += ['--threshold', str(threshold)]
    for key in ['accuracy', 'smoothing', 'corner_threshold', 'min_contour_area', 'grid', 'structure_grid']:
        v = values[key]
        if not number(v) or v < 0 or (key in ('accuracy','smoothing','corner_threshold') and v == 0):
            raise CompanionError('Invalid ' + key.replace('_', ' '))
        if key == 'corner_threshold' and v >= 180:
            raise CompanionError('Corner threshold must be below 180 degrees')
        if key in ('grid', 'structure_grid') and (type(v) is not int or v > 1000000):
            raise CompanionError('Grid must be an integer between 0 and 1,000,000')
        args += ['--' + key.replace('_', '-'), str(v)]
    for key in ['invert', 'rtl_start', 'refine_raster']:
        if type(values[key]) is not bool:
            raise CompanionError('Invalid boolean option: ' + key)
    for key in ['invert', 'rtl_start']:
        if values[key]:
            args += ['--' + key.replace('_', '-')]
    args += ['--refine-raster' if values['refine_raster'] else '--no-refine-raster']
    return args


def run_process(executable, args, source, cancel, timeout, output_limit=MAX_OUTPUT):
    """Multiplex all three pipes so neither stdin nor stderr can deadlock us."""
    if cancel.is_set():
        raise Cancelled('Trace cancelled')
    executable = str(Path(executable).expanduser())
    if not os.path.isabs(executable) or not os.path.isfile(executable) or not os.access(executable, os.X_OK):
        raise CompanionError('Choose a compatible beztrace executable in the ⋯ → Choose Engine… menu')
    try:
        process = subprocess.Popen([executable] + list(args), stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=True, bufsize=0)
    except OSError as exc:
        raise CompanionError('Cannot launch engine: ' + str(exc)) from exc
    selector = selectors.DefaultSelector()
    streams = (process.stdin, process.stdout, process.stderr)
    out, err = bytearray(), bytearray()
    offset = 0
    deadline = time.monotonic() + timeout
    try:
        for stream in streams:
            os.set_blocking(stream.fileno(), False)
        selector.register(process.stdout, selectors.EVENT_READ, out)
        selector.register(process.stderr, selectors.EVENT_READ, err)
        if source:
            selector.register(process.stdin, selectors.EVENT_WRITE, None)
        else:
            process.stdin.close()
        while selector.get_map() or process.poll() is None:
            if cancel.is_set():
                raise Cancelled('Trace cancelled')
            if time.monotonic() >= deadline:
                raise CompanionError('Engine timed out after %g seconds' % timeout)
            for key, _ in selector.select(0.05):
                stream = key.fileobj
                if key.events == selectors.EVENT_WRITE:
                    try:
                        offset += os.write(stream.fileno(), source[offset:offset+65536])
                    except BrokenPipeError:
                        offset = len(source)
                    if offset == len(source):
                        selector.unregister(stream)
                        stream.close()
                else:
                    chunk = os.read(stream.fileno(), 65536)
                    if not chunk:
                        selector.unregister(stream)
                        stream.close()
                    else:
                        key.data.extend(chunk)
                        if len(key.data) > (output_limit if key.data is out else 65536):
                            raise CompanionError('Engine output exceeded its buffer limit')
        return process.wait(), bytes(out), bytes(err)
    finally:
        selector.close()
        # Also stop descendants holding a pipe open, even if the leader exited.
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=0.25)
        except subprocess.TimeoutExpired:
            pass
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        for stream in streams:
            stream.close()


def trace(executable, image, options, cancel=None, progress=lambda stage: None,
          version_timeout=5, trace_timeout=60):
    cancel = cancel or threading.Event()
    if not image:
        raise CompanionError('Select a nonempty PNG or JPEG image')
    if len(image) > MAX_INPUT:
        raise CompanionError('Image exceeds the engine limit of 16 MiB')
    args = arguments(options)
    progress('Checking engine…')
    code, out, err = run_process(executable, ['--version'], b'', cancel, version_timeout, 4096)
    versions = {('beztrace ' + version).encode(): version for version in ENGINE_VERSIONS}
    if code or out.strip() not in versions or err:
        raise CompanionError('Incompatible engine: beztrace 0.1.0 or 0.1.1-dev.1 is required')
    checked_version = versions[out.strip()]
    progress('Tracing…')
    code, out, err = run_process(executable, args, image, cancel, trace_timeout)
    if code:
        detail = err.decode('utf-8', 'replace')[:1500].strip()
        try:
            envelope = json.loads(err)
            if envelope.get('schemaVersion') == 1 and envelope.get('exitCode') == code and isinstance(envelope.get('error', {}).get('message'), str):
                detail = envelope['error']['message'][:1500]
        except (ValueError, AttributeError, TypeError, RecursionError):
            pass
        raise CompanionError(EXIT_ERRORS.get(code, 'Engine exited with status %s' % code) + (': ' + detail if detail else ''))
    if cancel.is_set():
        raise Cancelled('Trace cancelled')
    progress('Validating outlines…')
    result = parse_result(out, image, expected_engine_version=checked_version)
    if cancel.is_set():
        raise Cancelled('Trace cancelled')
    return result

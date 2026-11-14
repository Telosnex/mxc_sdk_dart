// Ported from @microsoft/mxc-sdk 1.0.1, sdk/node/src/v1/container-process.ts
// and the lifecycle driver of sdk/node/src/bindings/streaming.ts.
// Copyright (c) Microsoft Corporation. Licensed under the MIT License.
//
// mxc_ffi requires that calls on one sandbox handle do not overlap. This
// isolate makes each of them, except mxc_spawn_json and mxc_sandbox_free,
// which can block: a helper isolate makes those, while no other call on the
// handle can run. Completion is polled with mxc_sandbox_try_wait, as the
// Node SDK does, so a kill never overlaps a blocking wait.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'errors.dart';
import 'native/bindings.dart';
import 'native/native_error.dart';
import 'native/stdio.dart';
import 'request.dart';
import 'types.dart';

const _pollInterval = Duration(milliseconds: 100);

/// Starts [request] and returns its live process.
///
/// Throws [MxcError] off Windows or when MXC cannot start it.
Future<MxcProcess> spawn(ContainerRequest request) async {
  final prepared = prepareContainerRequest(request);
  if (!Platform.isWindows) {
    throw const MxcError(
      MxcErrorCode.backendUnavailable,
      'mxc_sdk_dart can start containers only on Windows',
    );
  }
  final json = jsonEncode(prepared);
  final timeout = prepared['process'] as Map<String, Object?>;
  final result = await Isolate.run(() => _spawnNative(json));
  if (result case (final int address, null)) {
    return MxcProcess._(
      Pointer<MxcSandbox>.fromAddress(address),
      timeout['timeout'] as int,
    );
  }
  throw result.$2!;
}

(int?, MxcError?) _spawnNative(String json) => using((arena) {
  final handle = arena<Pointer<MxcSandbox>>();
  final error = arena<MxcErrorDetail>();
  final status = mxcSpawnJson(
    json.toNativeUtf8(allocator: arena),
    0,
    handle,
    error,
  );
  if (status != 0) return (null, takeNativeError(status, error));
  if (handle.value == nullptr) {
    return (
      null,
      const MxcError(
        MxcErrorCode.backendError,
        'native runtime returned a null lifecycle handle',
      ),
    );
  }
  return (handle.value.address, null);
});

enum _Phase { active, settling, terminal, disposed }

/// A process in an MXC container.
///
/// Listen to [standardOutput] and [standardError] before [wait]. Waiting
/// drains a stream that has no listener, and it is then unavailable.
final class MxcProcess {
  MxcProcess._(this._handle, int timeoutMs)
    : id = mxcSandboxId(_handle),
      _deadline = timeoutMs > 0
          ? DateTime.now().add(Duration(milliseconds: timeoutMs))
          : null {
    final stdin = mxcSandboxTakeStdin(_handle);
    _stdin = stdin == nullptr ? null : NativeStdin.start(stdin);
    final stdout = mxcSandboxTakeStdout(_handle);
    _stdout = stdout == nullptr ? null : readNativeStream(stdout);
    final stderr = mxcSandboxTakeStderr(_handle);
    _stderr = stderr == nullptr ? null : readNativeStream(stderr);
    try {
      _warnings = _readWarnings();
    } on MxcError {
      _stdin?.close();
      _drain(_stdout);
      _drain(_stderr);
      _freeInBackground();
      rethrow;
    }
    _poll();
  }

  final Pointer<MxcSandbox> _handle;

  /// The OS process ID, or 0 when the backend has none.
  final int id;

  final DateTime? _deadline;
  NativeStdin? _stdin;
  Stream<List<int>>? _stdout;
  Stream<List<int>>? _stderr;
  bool _stdinTaken = false;
  bool _stdoutTaken = false;
  bool _stderrTaken = false;
  bool _stdoutDrained = false;
  bool _stderrDrained = false;
  late List<String> _warnings;
  var _phase = _Phase.active;
  bool _killRequested = false;
  Timer? _pollTimer;
  final _result = Completer<WaitResult>();

  /// The stdin of the process. The caller closes it. Null when the backend
  /// has none.
  NativeStdin? get standardInput {
    _throwIfDisposed();
    _stdinTaken = true;
    return _stdin;
  }

  Stream<List<int>>? get standardOutput {
    _throwIfDisposed();
    if (_stdoutDrained) {
      throw StateError(
        'standard output is unavailable because wait() began draining it; '
        'access the stream before awaiting process completion',
      );
    }
    _stdoutTaken = true;
    return _stdout;
  }

  Stream<List<int>>? get standardError {
    _throwIfDisposed();
    if (_stderrDrained) {
      throw StateError(
        'standard error is unavailable because wait() began draining it; '
        'access the stream before awaiting process completion',
      );
    }
    _stderrTaken = true;
    return _stderr;
  }

  /// Warnings of the spawn, updated when the process ends.
  List<String> get warnings => _warnings;

  /// Completes when the process ends. Closes stdin and drains each output
  /// stream that the caller did not take. The native handle is freed first.
  Future<WaitResult> wait() {
    _throwIfDisposed();
    if (!_stdinTaken) _stdin?.close();
    if (!_stdoutTaken && !_stdoutDrained) {
      _stdoutDrained = true;
      _drain(_stdout);
    }
    if (!_stderrTaken && !_stderrDrained) {
      _stderrDrained = true;
      _drain(_stderr);
    }
    return _result.future;
  }

  /// Ends the process and every process it started.
  void kill() {
    _throwIfDisposed();
    if (_phase != _Phase.active || _killRequested) return;
    _check(mxcSandboxKill(_handle), 'killing sandbox process failed');
    _killRequested = true;
  }

  /// Ends the process if it runs, and frees it. [wait] then fails.
  void dispose() {
    if (_phase == _Phase.disposed) return;
    final previous = _phase;
    _phase = _Phase.disposed;
    _pollTimer?.cancel();
    Object? firstError;
    if (previous == _Phase.active && !_killRequested) {
      try {
        _check(mxcSandboxKill(_handle), 'killing sandbox process failed');
        _killRequested = true;
      } on Object catch (error) {
        firstError = error;
      }
    }
    if (!_stdinTaken) _stdin?.close();
    // A free kills the process tree, which ends the output streams.
    if (previous == _Phase.active) _freeInBackground();
    if (previous != _Phase.terminal) {
      _result.future.ignore();
      _result.completeError(
        StateError('sandbox process was disposed before completion'),
      );
    }
    if (firstError != null) throw firstError;
  }

  void _poll() {
    if (_phase != _Phase.active) return;
    final ({int exitCode, bool running, bool timedOut}) status;
    try {
      status = _tryWait();
    } on Object catch (error) {
      _finish(error: error);
      return;
    }
    if (!status.running) {
      _finish(
        result: WaitResult(
          exitCode: status.exitCode,
          timedOut: status.timedOut,
        ),
      );
      return;
    }
    final deadline = _deadline;
    final now = DateTime.now();
    if (deadline != null && !now.isBefore(deadline)) {
      _finishAfterTimeout();
      return;
    }
    final remaining = deadline?.difference(now);
    _pollTimer = Timer(
      remaining != null && remaining < _pollInterval
          ? remaining
          : _pollInterval,
      _poll,
    );
  }

  void _finishAfterTimeout() {
    try {
      _check(
        mxcSandboxKillForTimeout(_handle),
        'killing timed-out sandbox process failed',
      );
    } on Object catch (error) {
      _finish(error: error);
      return;
    }
    _killRequested = true;
    _finish(result: const WaitResult(exitCode: -1, timedOut: true));
  }

  /// Settles the process: reaps it if a kill is pending, reads its last
  /// warnings, frees it, then completes [wait].
  Future<void> _finish({WaitResult? result, Object? error}) async {
    if (_phase != _Phase.active) return;
    _phase = _Phase.settling;
    _pollTimer?.cancel();
    if (error == null && result != null && _killRequested) {
      // After a kill, wait for the tree to end without blocking this isolate.
      try {
        while (_phase != _Phase.disposed && _tryWait().running) {
          await Future<void>.delayed(_pollInterval);
        }
      } on Object catch (cause) {
        error = cause;
      }
    }
    // A dispose during settling leaves the free to this method.
    if (_phase != _Phase.disposed) {
      try {
        _warnings = _readWarnings();
      } on Object catch (cause) {
        error ??= cause;
      }
    }
    final address = _handle.address;
    try {
      await Isolate.run(
        () => mxcSandboxFree(Pointer<MxcSandbox>.fromAddress(address)),
      );
    } on Object catch (cause) {
      error ??= cause;
    }
    if (_phase == _Phase.disposed) return;
    _phase = _Phase.terminal;
    if (error != null) {
      _result.completeError(error);
    } else {
      _result.complete(result);
    }
  }

  ({int exitCode, bool running, bool timedOut}) _tryWait() => using((arena) {
    final exit = arena<Int32>();
    final running = arena<Int32>()..value = 1;
    final timedOut = arena<Int32>();
    _check(
      mxcSandboxTryWait(_handle, exit, running, timedOut),
      'polling sandbox process failed',
    );
    return (
      exitCode: exit.value,
      running: running.value != 0,
      timedOut: timedOut.value != 0,
    );
  });

  List<String> _readWarnings() => using((arena) {
    final out = arena<Pointer<Utf8>>();
    _check(
      mxcSandboxWarningsJson(_handle, out),
      'reading sandbox process warnings failed',
    );
    final pointer = out.value;
    if (pointer == nullptr) return const <String>[];
    try {
      final value = jsonDecode(pointer.toDartString());
      if (value is! List || value.any((entry) => entry is! String)) {
        throw const MxcError(
          MxcErrorCode.backendError,
          'native runtime returned malformed warnings',
        );
      }
      return value.cast<String>();
    } finally {
      mxcStringFree(pointer);
    }
  });

  void _freeInBackground() {
    final address = _handle.address;
    unawaited(
      Isolate.run(
        () => mxcSandboxFree(Pointer<MxcSandbox>.fromAddress(address)),
      ).catchError((Object _) {}),
    );
  }

  void _throwIfDisposed() {
    if (_phase == _Phase.disposed) {
      throw StateError('sandbox process has been disposed');
    }
  }
}

void _drain(Stream<List<int>>? stream) {
  stream?.listen(null, onError: (Object _) {});
}

void _check(int status, String message) {
  if (status != 0) throw nativeStatusError(status, fallback: message);
}

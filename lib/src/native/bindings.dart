// Bindings for the C ABI of mxc_ffi (microsoft/mxc v1.0.1,
// src/ffi/mxc_ffi/src). The build hook bundles the library as the code asset
// below. Each function is safe to call from any isolate.
@DefaultAsset('package:mxc_sdk_dart/mxc_ffi')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class MxcSandbox extends Opaque {}

final class MxcReadStream extends Opaque {}

final class MxcWriteStream extends Opaque {}

final class MxcStreamCloser extends Opaque {}

/// `MxcErrorDetail`. Each non-null field is owned by the caller and freed by
/// [mxcErrorDetailFree].
final class MxcErrorDetail extends Struct {
  external Pointer<Utf8> message;
  external Pointer<Utf8> operation;
  external Pointer<Utf8> nativeCode;
  external Pointer<Utf8> remediation;
}

@Native<
  Int32 Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>, Pointer<MxcErrorDetail>)
>(symbol: 'mxc_probe_request_json_with_error')
external int mxcProbeRequestJsonWithError(
  Pointer<Utf8> requestJson,
  Pointer<Pointer<Utf8>> outJson,
  Pointer<MxcErrorDetail> outError,
);

@Native<
  Int32 Function(
    Pointer<Utf8>,
    Int32,
    Pointer<Pointer<MxcSandbox>>,
    Pointer<MxcErrorDetail>,
  )
>(symbol: 'mxc_spawn_json')
external int mxcSpawnJson(
  Pointer<Utf8> requestJson,
  int experimental,
  Pointer<Pointer<MxcSandbox>> outHandle,
  Pointer<MxcErrorDetail> outError,
);

@Native<Void Function(Pointer<MxcErrorDetail>)>(symbol: 'mxc_error_detail_free')
external void mxcErrorDetailFree(Pointer<MxcErrorDetail> detail);

@Native<Void Function(Pointer<Utf8>)>(symbol: 'mxc_string_free')
external void mxcStringFree(Pointer<Utf8> value);

@Native<Uint32 Function(Pointer<MxcSandbox>)>(symbol: 'mxc_sandbox_id')
external int mxcSandboxId(Pointer<MxcSandbox> handle);

@Native<Pointer<MxcWriteStream> Function(Pointer<MxcSandbox>)>(
  symbol: 'mxc_sandbox_take_stdin',
)
external Pointer<MxcWriteStream> mxcSandboxTakeStdin(
  Pointer<MxcSandbox> handle,
);

@Native<Pointer<MxcReadStream> Function(Pointer<MxcSandbox>)>(
  symbol: 'mxc_sandbox_take_stdout',
)
external Pointer<MxcReadStream> mxcSandboxTakeStdout(
  Pointer<MxcSandbox> handle,
);

@Native<Pointer<MxcReadStream> Function(Pointer<MxcSandbox>)>(
  symbol: 'mxc_sandbox_take_stderr',
)
external Pointer<MxcReadStream> mxcSandboxTakeStderr(
  Pointer<MxcSandbox> handle,
);

@Native<Pointer<MxcStreamCloser> Function(Pointer<MxcSandbox>)>(
  symbol: 'mxc_sandbox_stdout_closer',
)
external Pointer<MxcStreamCloser> mxcSandboxStdoutCloser(
  Pointer<MxcSandbox> handle,
);

@Native<Pointer<MxcStreamCloser> Function(Pointer<MxcSandbox>)>(
  symbol: 'mxc_sandbox_stderr_closer',
)
external Pointer<MxcStreamCloser> mxcSandboxStderrCloser(
  Pointer<MxcSandbox> handle,
);

@Native<Int32 Function(Pointer<MxcStreamCloser>)>(
  symbol: 'mxc_stream_closer_close',
)
external int mxcStreamCloserClose(Pointer<MxcStreamCloser> closer);

@Native<Void Function(Pointer<MxcStreamCloser>)>(
  symbol: 'mxc_stream_closer_free',
)
external void mxcStreamCloserFree(Pointer<MxcStreamCloser> closer);

@Native<
  Int32 Function(Pointer<MxcReadStream>, Pointer<Uint8>, Size, Pointer<Size>)
>(symbol: 'mxc_stream_read')
external int mxcStreamRead(
  Pointer<MxcReadStream> stream,
  Pointer<Uint8> buffer,
  int capacity,
  Pointer<Size> outRead,
);

@Native<
  Int32 Function(Pointer<MxcWriteStream>, Pointer<Uint8>, Size, Pointer<Size>)
>(symbol: 'mxc_stream_write')
external int mxcStreamWrite(
  Pointer<MxcWriteStream> stream,
  Pointer<Uint8> buffer,
  int length,
  Pointer<Size> outWritten,
);

@Native<Int32 Function(Pointer<MxcWriteStream>)>(symbol: 'mxc_stream_flush')
external int mxcStreamFlush(Pointer<MxcWriteStream> stream);

@Native<Void Function(Pointer<MxcReadStream>)>(symbol: 'mxc_read_stream_free')
external void mxcReadStreamFree(Pointer<MxcReadStream> stream);

@Native<Void Function(Pointer<MxcWriteStream>)>(symbol: 'mxc_write_stream_free')
external void mxcWriteStreamFree(Pointer<MxcWriteStream> stream);

@Native<
  Int32 Function(
    Pointer<MxcSandbox>,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
>(symbol: 'mxc_sandbox_try_wait')
external int mxcSandboxTryWait(
  Pointer<MxcSandbox> handle,
  Pointer<Int32> outExit,
  Pointer<Int32> outRunning,
  Pointer<Int32> outTimedOut,
);

@Native<Int32 Function(Pointer<MxcSandbox>)>(symbol: 'mxc_sandbox_kill')
external int mxcSandboxKill(Pointer<MxcSandbox> handle);

@Native<Int32 Function(Pointer<MxcSandbox>)>(
  symbol: 'mxc_sandbox_kill_for_timeout',
)
external int mxcSandboxKillForTimeout(Pointer<MxcSandbox> handle);

@Native<Int32 Function(Pointer<MxcSandbox>, Pointer<Pointer<Utf8>>)>(
  symbol: 'mxc_sandbox_warnings_json',
)
external int mxcSandboxWarningsJson(
  Pointer<MxcSandbox> handle,
  Pointer<Pointer<Utf8>> outJson,
);

@Native<Void Function(Pointer<MxcSandbox>)>(symbol: 'mxc_sandbox_free')
external void mxcSandboxFree(Pointer<MxcSandbox> handle);

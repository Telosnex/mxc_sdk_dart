// Blocking stream I/O of mxc_ffi, each stream driven by one helper isolate.
// The C ABI allows that: each stream handle is its own object, and only one
// thread uses it at a time.

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

const _readCapacity = 64 * 1024;

/// Reads [stream] to its end in a helper isolate. The returned stream emits
/// each chunk, and the reader frees [stream] after the last read.
Stream<List<int>> readNativeStream(Pointer<MxcReadStream> stream) {
  final port = ReceivePort();
  final controller = StreamController<List<int>>();
  late final StreamSubscription<Object?> subscription;
  subscription = port.listen((message) {
    switch (message) {
      case final TransferableTypedData chunk:
        controller.add(chunk.materialize().asUint8List());
      case final String error:
        controller.addError(StateError(error));
      case null:
        subscription.cancel();
        port.close();
        controller.close();
    }
  });
  Isolate.spawn(_readLoop, (
    port.sendPort,
    stream.address,
  ), debugName: 'mxc stream reader').catchError((Object error) {
    // The isolate did not start, so free the stream here.
    mxcReadStreamFree(stream);
    controller
      ..addError(error)
      ..close();
    port.close();
    return Isolate.current;
  });
  return controller.stream;
}

void _readLoop((SendPort, int) arguments) {
  final (port, address) = arguments;
  final stream = Pointer<MxcReadStream>.fromAddress(address);
  final buffer = calloc<Uint8>(_readCapacity);
  final count = calloc<Size>();
  try {
    while (true) {
      final status = mxcStreamRead(stream, buffer, _readCapacity, count);
      if (status != 0) {
        port.send('reading sandbox output failed with status $status');
        break;
      }
      final read = count.value;
      if (read == 0) break;
      port.send(
        TransferableTypedData.fromList([
          Uint8List.fromList(buffer.asTypedList(read)),
        ]),
      );
    }
  } finally {
    calloc
      ..free(buffer)
      ..free(count);
    mxcReadStreamFree(stream);
    port.send(null);
  }
}

/// The stdin of a sandboxed process. Writes go to a helper isolate in order.
final class NativeStdin {
  NativeStdin._(this._commands, this._done);

  final Future<SendPort> _commands;
  final Future<void> _done;
  bool _closed = false;

  /// Starts the writer of [stream]. The writer frees [stream] on [close].
  static NativeStdin start(Pointer<MxcWriteStream> stream) {
    final port = ReceivePort();
    final commands = Completer<SendPort>();
    final done = Completer<void>();
    port.listen((message) {
      switch (message) {
        case final SendPort sendPort:
          commands.complete(sendPort);
        case null:
          port.close();
          done.complete();
      }
    });
    Isolate.spawn(_writeLoop, (
      port.sendPort,
      stream.address,
    ), debugName: 'mxc stdin writer').catchError((Object error) {
      mxcWriteStreamFree(stream);
      port.close();
      commands.completeError(error);
      done.complete();
      return Isolate.current;
    });
    return NativeStdin._(commands.future, done.future);
  }

  /// Queues [data]. Bytes after a failed write are dropped, as a closed pipe
  /// drops them.
  void add(List<int> data) {
    if (_closed) throw StateError('stdin is closed');
    if (data.isEmpty) return;
    final bytes = TransferableTypedData.fromList([Uint8List.fromList(data)]);
    _commands.then((port) => port.send(bytes), onError: (Object _) {});
  }

  /// Sends end-of-file to the process.
  Future<void> close() {
    if (!_closed) {
      _closed = true;
      _commands.then((port) => port.send(null), onError: (Object _) {});
    }
    return _done;
  }
}

void _writeLoop((SendPort, int) arguments) {
  final (port, address) = arguments;
  final stream = Pointer<MxcWriteStream>.fromAddress(address);
  final commands = ReceivePort();
  var failed = false;
  commands.listen((message) {
    if (message case final TransferableTypedData chunk when !failed) {
      final data = chunk.materialize().asUint8List();
      final buffer = calloc<Uint8>(data.length);
      final written = calloc<Size>();
      try {
        buffer.asTypedList(data.length).setAll(0, data);
        var offset = 0;
        while (offset < data.length) {
          final status = mxcStreamWrite(
            stream,
            buffer + offset,
            data.length - offset,
            written,
          );
          if (status != 0 || written.value == 0) {
            failed = true;
            break;
          }
          offset += written.value;
        }
        if (!failed) mxcStreamFlush(stream);
      } finally {
        calloc
          ..free(buffer)
          ..free(written);
      }
    } else if (message == null) {
      mxcWriteStreamFree(stream);
      commands.close();
      port.send(null);
    }
  });
  port.send(commands.sendPort);
}

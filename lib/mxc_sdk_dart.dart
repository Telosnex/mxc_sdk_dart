/// Dart port of the Microsoft MXC SDK subset that sandbox-runtime uses.
///
/// [probe] tells whether Windows can enforce a request, and [spawn] starts
/// it in a Windows ProcessContainer. Both call mxc_ffi.dll in process.
library;

export 'src/errors.dart' show MxcError, MxcErrorCode;
export 'src/native/stdio.dart' show NativeStdin;
export 'src/probe.dart' show probe;
export 'src/process.dart' show MxcProcess, spawn;
export 'src/request.dart' show prepareContainerRequest, sdkContractVersion;
export 'src/types.dart';

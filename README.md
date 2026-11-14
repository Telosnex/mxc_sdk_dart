# mxc_sdk_dart

A Dart port of the part of the Microsoft MXC SDK (`@microsoft/mxc-sdk`) that
[sandbox-runtime](https://github.com/anthropics/sandbox-runtime) uses. It
starts a command in a Windows ProcessContainer (BaseContainer), in process,
through `mxc_ffi.dll`.

```dart
import 'package:mxc_sdk_dart/mxc_sdk_dart.dart';

final request = ContainerRequest(
  command: r'C:\Windows\System32\cmd.exe /d /s /c "echo hi"',
  filesystem: FilesystemPolicy(
    readwritePaths: [r'C:\work'],
    readonlyPaths: [r'C:\'],
  ),
  network: NetworkPolicy(
    egress: NetworkEgressConfig(defaultAction: NetworkAction.deny),
  ),
  ui: UiPolicy(disable: false),
  workingDirectory: r'C:\work',
  inheritDefaultEnvironment: true,
);
if (probe(request).tier == IsolationTier.baseContainer) {
  final process = await spawn(request);
  process.standardOutput!.listen(stdout.add);
  print(await process.wait());
}
```

## Scope

| Node SDK (`@microsoft/mxc-sdk/v1`) | Here |
|---|---|
| `probe(request)` | `probe(request)` |
| `spawn(request)`, `MxcProcess` | `spawn(request)`, `MxcProcess` |
| `ContainerRequest` | The same, for containments `process` and `processcontainer` |
| `run`, `spawnWithPty`, lifecycle APIs, telemetry, other backends | Not ported |

Off Windows, `probe` and `spawn` throw `MxcError` with
`MxcErrorCode.backendUnavailable`, and the package bundles no library.

Differences from the Node SDK:

- stdout and stderr are `Stream<List<int>>`, and stdin is a `NativeStdin`.
  A helper isolate drives each one with the blocking stream functions of
  `mxc_ffi`.
- After a kill or a timeout, completion is polled with
  `mxc_sandbox_try_wait`, not waited on in a blocking call. The C ABI does
  not allow a kill during a blocking wait.

## The native library

The build hook uses [kiln](https://github.com/Telosnex/kiln). It downloads
`mxc_ffi.dll` from a GitHub release when `native_artifacts/prebuilt.json`
matches the package sources. Otherwise it builds the `mxc_ffi` crate of
microsoft/mxc at the commit in `native_artifacts/sources.json` (tag
`v1.0.1`). A source build needs Windows, rustup, and the Rust target:

```
rustup target add aarch64-pc-windows-msvc x86_64-pc-windows-msvc
```

## Tests

`dart test` runs everywhere. On Windows 11 with BaseContainer, it also runs
`test/windows_test.dart`, which starts real containers.

## License

MIT. The ported files keep the copyright of Microsoft Corporation, from
microsoft/mxc `sdk/node` (MIT).

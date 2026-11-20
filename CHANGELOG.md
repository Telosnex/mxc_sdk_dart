## 0.1.2

- Add a runnable example that checks whether MXC can enforce a container
  request without launching it.

## 0.1.1

- `mxc_ffi.dll` is built from microsoft/mxc v1.1.0. The Dart API is unchanged.
- The library is built without Microsoft telemetry routing: MXC 1.1.0 would
  otherwise send Required diagnostic events to Microsoft. The build hook fails
  if the built library contains MXC's routing group.
- MXC 1.1.0 removes the AppContainer fallback tiers of ProcessContainer. A
  host without BaseContainer support is rejected before launch.

## 0.1.0

- First release: `probe`, `spawn`, and `MxcProcess`, ported from
  `@microsoft/mxc-sdk` 1.0.1. `mxc_ffi.dll` built from microsoft/mxc
  v1.0.1 by a kiln build hook.

// Ported from @microsoft/mxc-sdk 1.0.1, sdk/node/src/bindings/native-error.ts.
// Copyright (c) Microsoft Corporation. Licensed under the MIT License.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../errors.dart';
import 'bindings.dart';

/// An [MxcError] for [status], with the fields of [detail]. Frees [detail].
MxcError takeNativeError(int status, Pointer<MxcErrorDetail> detail) {
  String? read(Pointer<Utf8> value) =>
      value == nullptr ? null : value.toDartString();
  try {
    final fields = detail.ref;
    return nativeStatusError(
      status,
      message: read(fields.message),
      operation: read(fields.operation),
      nativeCode: read(fields.nativeCode),
      remediation: read(fields.remediation),
    );
  } finally {
    mxcErrorDetailFree(detail);
  }
}

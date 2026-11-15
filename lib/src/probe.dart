// Ported from @microsoft/mxc-sdk 1.1.0, sdk/node/src/v1/probe.ts and
// sdk/node/src/bindings/probe.ts.
// Copyright (c) Microsoft Corporation. Licensed under the MIT License.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'errors.dart';
import 'native/bindings.dart';
import 'native/native_error.dart';
import 'request.dart';
import 'types.dart';

/// Which Windows ProcessContainer tier can serve [request].
///
/// Synchronous. It does not create a container.
///
/// Throws [MxcError] off Windows, when the native probe fails, or when it
/// returns malformed JSON.
ProbeOutput probe([ContainerRequest? request]) {
  final requestJson = request == null
      ? null
      : jsonEncode(prepareContainerRequest(request));
  if (!Platform.isWindows) {
    throw const MxcError(
      MxcErrorCode.backendUnavailable,
      'the request-aware probe is available only for Windows '
      'ProcessContainer',
    );
  }
  final responseJson = readProbeJson(requestJson);
  final Object? value;
  try {
    value = jsonDecode(responseJson);
  } on FormatException catch (error) {
    throw MxcError(
      MxcErrorCode.backendError,
      'invalid request probe JSON from mxc_ffi: ${error.message}',
    );
  }
  return parseProbeOutput(value) ??
      (throw const MxcError(
        MxcErrorCode.backendError,
        'invalid request probe output from mxc_ffi',
      ));
}

/// Calls the native probe and frees what it returns.
String readProbeJson(String? requestJson) => using((arena) {
  final request = requestJson == null
      ? nullptr.cast<Utf8>()
      : requestJson.toNativeUtf8(allocator: arena);
  final output = arena<Pointer<Utf8>>();
  final error = arena<MxcErrorDetail>();
  final status = mxcProbeRequestJsonWithError(request, output, error);
  if (status != 0) throw takeNativeError(status, error);
  final pointer = output.value;
  if (pointer == nullptr) {
    throw const MxcError(
      MxcErrorCode.backendError,
      'native request probe returned a null success result',
    );
  }
  try {
    return pointer.toDartString();
  } finally {
    mxcStringFree(pointer);
  }
});

/// The probe output in [value], or null if [value] does not have exactly the
/// shape of the contract.
ProbeOutput? parseProbeOutput(Object? value) {
  const keys = {'tier', 'needsDaclAugmentation', 'warnings', 'probes', 'error'};
  if (value is! Map<String, Object?> || !value.keys.every(keys.contains)) {
    return null;
  }
  final warnings = value['warnings'];
  if (warnings is! List || warnings.any((entry) => entry is! String)) {
    return null;
  }
  final probes = _parseFacts(value['probes']);
  if (probes == null) return null;
  final rawTier = value['tier'];
  final dacl = value['needsDaclAugmentation'];
  final error = value['error'];
  if (rawTier != null) {
    final tier = IsolationTier.fromWire(rawTier);
    if (tier == null || dacl is! bool || error != null) return null;
    return ProbeOutput(
      tier: tier,
      needsDaclAugmentation: dacl,
      warnings: warnings.cast<String>(),
      probes: probes,
    );
  }
  if (error is! String || dacl != null) return null;
  return ProbeOutput(
    warnings: warnings.cast<String>(),
    probes: probes,
    error: error,
  );
}

ProbeFacts? _parseFacts(Object? value) {
  final keys = {...ProbeFacts.booleanFields, 'uiCapabilities'};
  if (value is! Map<String, Object?> || !value.keys.every(keys.contains)) {
    return null;
  }
  final booleans = _booleans(value, ProbeFacts.booleanFields);
  final ui = value['uiCapabilities'];
  if (booleans == null || ui is! Map<String, Object?>) return null;
  if (!ui.keys.every(UiCapabilitySupport.fields.contains)) return null;
  final uiBooleans = _booleans(ui, UiCapabilitySupport.fields);
  if (uiBooleans == null) return null;
  return ProbeFacts(booleans, UiCapabilitySupport(uiBooleans));
}

Map<String, bool>? _booleans(Map<String, Object?> json, List<String> fields) {
  final result = <String, bool>{};
  for (final field in fields) {
    final value = json[field];
    if (value is! bool) return null;
    result[field] = value;
  }
  return result;
}

// Ported from @microsoft/mxc-sdk 1.0.1, sdk/node/src/v1/errors.ts and
// sdk/node/src/bindings/native-error.ts.
// Copyright (c) Microsoft Corporation. Licensed under the MIT License.

/// The error codes of the MXC wire contract.
enum MxcErrorCode {
  malformedRequest('malformed_request'),
  unsupportedContainment('unsupported_containment'),
  unsupportedPhase('unsupported_phase'),
  backendUnavailable('backend_unavailable'),
  malformedId('malformed_id'),
  staleId('stale_id'),
  notProvisioned('not_provisioned'),
  notStarted('not_started'),
  alreadyStarted('already_started'),
  alreadyStopped('already_stopped'),
  policyValidation('policy_validation'),
  backendError('backend_error');

  const MxcErrorCode(this.wire);

  /// The code as the wire contract spells it.
  final String wire;
}

/// A failure that MXC or this SDK reports.
final class MxcError implements Exception {
  const MxcError(
    this.code,
    this.message, {
    this.operation,
    this.nativeCode,
    this.remediation,
    this.ffiStatus,
  });

  final MxcErrorCode code;
  final String message;

  /// The API call that failed. Null when the failure came before any call.
  final String? operation;

  /// The platform status, for example `0x80070490`.
  final String? nativeCode;

  /// A hint to fix the failure.
  final String? remediation;

  /// The status that mxc_ffi returned, if the failure came from it.
  final int? ffiStatus;

  @override
  String toString() {
    final parts = [
      'MxcError(${code.wire}): $message',
      if (operation != null) 'operation: $operation',
      if (nativeCode != null) 'native code: $nativeCode',
      if (remediation != null) 'remediation: $remediation',
    ];
    return parts.join('; ');
  }
}

/// The error code for a status of mxc_ffi.
MxcErrorCode errorCodeForNativeStatus(int status) => switch (status) {
  1 || 100 || 101 => MxcErrorCode.malformedRequest,
  2 => MxcErrorCode.unsupportedContainment,
  3 => MxcErrorCode.unsupportedPhase,
  4 => MxcErrorCode.backendUnavailable,
  5 => MxcErrorCode.malformedId,
  6 => MxcErrorCode.staleId,
  7 => MxcErrorCode.notProvisioned,
  8 => MxcErrorCode.notStarted,
  9 => MxcErrorCode.alreadyStarted,
  10 => MxcErrorCode.alreadyStopped,
  11 => MxcErrorCode.policyValidation,
  _ => MxcErrorCode.backendError,
};

/// An [MxcError] for a failed status of mxc_ffi.
MxcError nativeStatusError(
  int status, {
  String? message,
  String? operation,
  String? nativeCode,
  String? remediation,
  String? fallback,
}) => MxcError(
  errorCodeForNativeStatus(status),
  message ?? fallback ?? 'native runtime failed with status $status',
  operation: operation,
  nativeCode: nativeCode,
  remediation: remediation,
  ffiStatus: status,
);

// Ported from @microsoft/mxc-sdk 1.1.0: createContainerConfig and
// prepareContainerRequest of sdk/node/src/v1/container.ts, and
// prepareOneShotRequest of sdk/node/src/bindings/one-shot.ts. The two steps
// make one function here, for the containments this SDK supports.
// Copyright (c) Microsoft Corporation. Licensed under the MIT License.

import 'dart:io';
import 'dart:math';

import 'errors.dart';
import 'types.dart';

/// The exact request contract of the v1 SDK.
const sdkContractVersion = '1.0.0';

const _u32Max = 0xffffffff;
const _u16Max = 0xffff;

Never _malformed(String message) =>
    throw MxcError(MxcErrorCode.malformedRequest, message);

/// 128 random bits as 32 hexadecimal characters.
String _randomContainerName() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 16; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// The JSON object that mxc_ffi accepts for [request].
///
/// [platform] is the host OS, as `Platform.operatingSystem` names it.
Map<String, Object?> prepareContainerRequest(
  ContainerRequest request, {
  String? platform,
}) {
  if (request.command.isEmpty) {
    _malformed('container request command must be a non-empty string');
  }
  final containment = request.containment ?? const ProcessContainment();
  final containerConfig = switch (containment) {
    ProcessContainerContainment(:final config) => config,
    ProcessContainment() => null,
  };

  final enumeratePaths = containerConfig?.enumeratePaths;
  if (enumeratePaths != null &&
      enumeratePaths.isNotEmpty &&
      (platform ?? Platform.operatingSystem) != 'windows') {
    _malformed(
      'containment.config.filesystem.enumeratePaths is supported only by the '
      'Windows ProcessContainer backend.',
    );
  }

  final timeout = request.timeoutMs ?? 0;
  if (timeout < 0 || timeout > _u32Max) {
    _malformed('process.timeout must be an integer between 0 and $_u32Max');
  }
  _validateNetworkPorts(request.network?.egress);

  final filesystem = request.filesystem ?? const FilesystemPolicy();
  final process = <String, Object?>{
    'commandLine': request.command,
    'timeout': timeout,
    'cwd': ?request.workingDirectory,
    if (request.environment case final environment?)
      'env': [
        for (final MapEntry(:key, :value) in environment.entries)
          if (value != null) '${_validName(key)}=$value',
      ],
    if (request.inheritDefaultEnvironment == true) 'inheritDefaultEnv': true,
  };

  final network = request.network;
  final directional = network?.egress != null || network?.ingress != null;
  final ui = request.ui;
  return {
    'version': sdkContractVersion,
    'containerId': request.containerName ?? _randomContainerName(),
    'containment': containment.wire,
    'lifecycle': {
      'destroyOnExit': true,
      'preservePolicy': !filesystem.clearPolicyOnExit,
    },
    'process': process,
    'filesystem': {
      'readwritePaths': [...filesystem.readwritePaths],
      'readonlyPaths': [...filesystem.readonlyPaths],
      'deniedPaths': [...filesystem.deniedPaths],
    },
    if (directional)
      'network': {
        if (network!.egress case final egress?) 'egress': egress.toJson(),
        if (network.ingress case final ingress?) 'ingress': ingress.toJson(),
      },
    if (network?.networkProxy case final proxy?)
      'runtimeConfig': {'networkProxy': proxy},
    if (ui != null)
      'ui': {
        'disable': ui.disable,
        'clipboard': ui.clipboard.wire,
        'injection': ui.allowInputInjection,
      },
    if (containment is ProcessContainerContainment)
      'processContainer': _processContainer(request, containerConfig),
  };
}

/// buildProcessBaseContainerConfig, the merge with the caller's config, and
/// the one-shot processContainer().
Map<String, Object?> _processContainer(
  ContainerRequest request,
  ProcessContainerConfig? config,
) {
  final egress = request.network?.egress;
  final ingress = request.network?.ingress;
  final directional = egress != null || ingress != null;
  final derived = [
    if (egress?.defaultAction == NetworkAction.allow ||
        (egress?.allow?.isNotEmpty ?? false))
      'internetClient',
    if (ingress?.defaultAction == NetworkAction.allow)
      'privateNetworkClientServer',
  ];
  final capabilities = config?.capabilities ?? derived;
  final ui = config?.ui ?? const BaseProcessUiConfig();
  return {
    'leastPrivilege': false,
    'capabilities': directional
        ? [
            for (final capability in capabilities)
              if (capability != 'internetClient' &&
                  capability != 'privateNetworkClientServer')
                capability,
          ]
        : [...capabilities],
    if (config?.learningMode == true) 'learningMode': true,
    if (config?.enumeratePaths case final paths?)
      'filesystem': {
        'enumeratePaths': [...paths],
      },
    if (config?.allowedProxyPeer case final peer?)
      'network': {'allowedProxyPeer': peer},
    if (!ui.isDefault) 'ui': ui.toJson(),
  };
}

String _validName(String name) {
  if (name.isEmpty || name.contains('=')) {
    _malformed("invalid environment variable name '$name'");
  }
  return name;
}

void _validateNetworkPorts(NetworkEgressConfig? egress) {
  final rules = [...?egress?.allow, ...?egress?.deny];
  for (final (ruleIndex, rule) in rules.indexed) {
    for (final (portIndex, port) in (rule.ports ?? const []).indexed) {
      final path = 'network.egress rule $ruleIndex port $portIndex';
      _range(port.port, '$path.port', 1, _u16Max);
      _range(port.endPort, '$path.endPort', 1, _u16Max);
      if (port.endPort case final end?) {
        final start = port.port;
        if (start == null) _malformed('$path.endPort requires port');
        if (end < start) {
          _malformed('$path.endPort must be greater than or equal to port');
        }
      }
    }
  }
}

void _range(int? value, String path, int min, int max) {
  if (value == null) return;
  if (value < min || value > max) {
    _malformed('$path must be an integer between $min and $max');
  }
}

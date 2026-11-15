// Ported from @microsoft/mxc-sdk 1.1.0, sdk/node/src/v1/types.ts: the request
// and probe types of the Windows ProcessContainer path.
// Copyright (c) Microsoft Corporation. Licensed under the MIT License.

/// `allow` or `deny`.
enum NetworkAction {
  allow,
  deny;

  String get wire => name;
}

enum NetworkProtocol {
  tcp,
  udp,
  icmp,
  any;

  String get wire => name;
}

final class NetworkPeerConfig {
  const NetworkPeerConfig({required this.cidr, this.except});

  final String cidr;
  final List<String>? except;

  Map<String, Object?> toJson() => {'cidr': cidr, 'except': ?except};
}

final class NetworkPortConfig {
  const NetworkPortConfig({this.protocol, this.port, this.endPort});

  final NetworkProtocol? protocol;
  final int? port;
  final int? endPort;

  Map<String, Object?> toJson() => {
    'protocol': ?protocol?.wire,
    'port': ?port,
    'endPort': ?endPort,
  };
}

final class NetworkRuleConfig {
  const NetworkRuleConfig({this.to, this.ports});

  final List<NetworkPeerConfig>? to;
  final List<NetworkPortConfig>? ports;

  Map<String, Object?> toJson() => {
    if (to case final to?) 'to': [for (final peer in to) peer.toJson()],
    if (ports case final ports?)
      'ports': [for (final port in ports) port.toJson()],
  };
}

final class NetworkEgressConfig {
  const NetworkEgressConfig({this.defaultAction, this.allow, this.deny});

  final NetworkAction? defaultAction;
  final List<NetworkRuleConfig>? allow;
  final List<NetworkRuleConfig>? deny;

  Map<String, Object?> toJson() => {
    'default': ?defaultAction?.wire,
    if (allow case final allow?)
      'allow': [for (final rule in allow) rule.toJson()],
    if (deny case final deny?) 'deny': [for (final rule in deny) rule.toJson()],
  };
}

final class NetworkIngressConfig {
  const NetworkIngressConfig({this.defaultAction, this.hostLoopback});

  final NetworkAction? defaultAction;

  /// Whether the container may reach the host's loopback.
  final NetworkAction? hostLoopback;

  Map<String, Object?> toJson() => {
    'default': ?defaultAction?.wire,
    'hostLoopback': ?hostLoopback?.wire,
  };
}

final class NetworkPolicy {
  const NetworkPolicy({this.egress, this.ingress, this.networkProxy});

  final NetworkEgressConfig? egress;
  final NetworkIngressConfig? ingress;

  /// `runtimeConfig.networkProxy`: the one proxy URL the container may use.
  final String? networkProxy;
}

final class FilesystemPolicy {
  const FilesystemPolicy({
    this.readwritePaths = const [],
    this.readonlyPaths = const [],
    this.deniedPaths = const [],
    this.clearPolicyOnExit = true,
  });

  final List<String> readwritePaths;
  final List<String> readonlyPaths;
  final List<String> deniedPaths;
  final bool clearPolicyOnExit;
}

enum ClipboardPolicy {
  none,
  read,
  write,
  all;

  String get wire => name;
}

final class UiPolicy {
  const UiPolicy({
    required this.disable,
    this.clipboard = ClipboardPolicy.none,
    this.allowInputInjection = false,
  });

  final bool disable;
  final ClipboardPolicy clipboard;
  final bool allowInputInjection;
}

/// UI settings of a BaseContainer.
final class BaseProcessUiConfig {
  const BaseProcessUiConfig({
    this.isolation = 'container',
    this.desktopSystemControl = false,
    this.systemSettings = 'none',
    this.ime = false,
  });

  /// `desktop`, `handles`, `atoms`, or `container`.
  final String isolation;
  final bool desktopSystemControl;
  final String systemSettings;
  final bool ime;

  bool get isDefault =>
      isolation == 'container' &&
      !desktopSystemControl &&
      systemSettings == 'none' &&
      !ime;

  Map<String, Object?> toJson() => {
    'isolation': isolation,
    'desktopSystemControl': desktopSystemControl,
    'systemSettings': systemSettings,
    'ime': ime,
  };
}

/// Settings of the Windows ProcessContainer backend.
final class ProcessContainerConfig {
  const ProcessContainerConfig({
    this.learningMode,
    this.capabilities,
    this.ui,
    this.enumeratePaths,
    this.allowedProxyPeer,
  });

  final bool? learningMode;

  /// AppContainer capabilities. With a directional network policy, MXC
  /// derives `internetClient` and `privateNetworkClientServer` itself.
  final List<String>? capabilities;
  final BaseProcessUiConfig? ui;

  /// Paths the command can list without reading their files.
  final List<String>? enumeratePaths;

  /// Package family name or AppContainer profile allowed as the loopback
  /// proxy peer.
  final String? allowedProxyPeer;
}

/// The backend of a request. This SDK supports the Windows backends only.
sealed class Containment {
  const Containment();

  String get wire;
}

/// MXC picks the backend for the platform.
final class ProcessContainment extends Containment {
  const ProcessContainment();

  @override
  String get wire => 'process';
}

final class ProcessContainerContainment extends Containment {
  const ProcessContainerContainment([this.config]);

  final ProcessContainerConfig? config;

  @override
  String get wire => 'processcontainer';
}

/// A command and the policy to run it with.
final class ContainerRequest {
  const ContainerRequest({
    required this.command,
    this.filesystem,
    this.network,
    this.ui,
    this.timeoutMs,
    this.containment,
    this.containerName,
    this.workingDirectory,
    this.environment,
    this.inheritDefaultEnvironment,
  });

  /// One command line, given to the OS as it is.
  final String command;
  final FilesystemPolicy? filesystem;
  final NetworkPolicy? network;
  final UiPolicy? ui;

  /// Null or 0: no timeout.
  final int? timeoutMs;

  /// Null: [ProcessContainment].
  final Containment? containment;

  /// Null: a random name.
  final String? containerName;
  final String? workingDirectory;

  /// A null value leaves the variable out.
  final Map<String, String?>? environment;

  /// Whether the child also gets the user's default environment.
  final bool? inheritDefaultEnvironment;
}

/// The isolation tier that MXC picked.
enum IsolationTier {
  baseContainer('base-container'),
  appContainerBfs('appcontainer-bfs'),
  appContainerDacl('appcontainer-dacl');

  const IsolationTier(this.wire);

  final String wire;

  static IsolationTier? fromWire(Object? value) {
    for (final tier in values) {
      if (tier.wire == value) return tier;
    }
    return null;
  }
}

final class UiCapabilitySupport {
  const UiCapabilitySupport(this.values);

  static const fields = [
    'canBlockClipboardRead',
    'canBlockClipboardWrite',
    'canBlockInputInjection',
    'canBlockInputMethodChanges',
    'canBlockExternalUiObjects',
    'canBlockGlobalUiNamespace',
    'canBlockDesktopSwitching',
    'canBlockLogoffOrShutdown',
    'canBlockSystemParameterChanges',
    'canBlockDisplaySettingsChanges',
  ];

  final Map<String, bool> values;

  bool get canBlockClipboardRead => values['canBlockClipboardRead']!;
  bool get canBlockClipboardWrite => values['canBlockClipboardWrite']!;
  bool get canBlockInputInjection => values['canBlockInputInjection']!;
}

final class ProbeFacts {
  const ProbeFacts(this.values, this.uiCapabilities);

  static const booleanFields = [
    'baseContainerApiPresent',
    'nativeCaptureAvailable',
    'guardedCaptureAvailable',
    'bfscfgPresent',
    'bfsCompiledIn',
    'baseContainerSupportsDenyPaths',
    'baseContainerSupportsEnumeratePaths',
    'baseContainerSupportsIngressHostLoopbackAllow',
    'baseContainerSupportsIdentitylessLoopbackProxy',
    'isolationSessionAvailable',
    'hyperlightAvailable',
  ];

  final Map<String, bool> values;
  final UiCapabilitySupport uiCapabilities;

  bool get baseContainerSupportsDenyPaths =>
      values['baseContainerSupportsDenyPaths']!;
  bool get baseContainerSupportsIngressHostLoopbackAllow =>
      values['baseContainerSupportsIngressHostLoopbackAllow']!;
  bool get baseContainerSupportsIdentitylessLoopbackProxy =>
      values['baseContainerSupportsIdentitylessLoopbackProxy']!;
}

/// The answer of [probe]. Exactly one of [tier] and [error] is non-null.
final class ProbeOutput {
  const ProbeOutput({
    this.tier,
    this.needsDaclAugmentation,
    required this.warnings,
    required this.probes,
    this.error,
  });

  final IsolationTier? tier;
  final bool? needsDaclAugmentation;
  final List<String> warnings;
  final ProbeFacts probes;
  final String? error;
}

/// How a process ended.
final class WaitResult {
  const WaitResult({required this.exitCode, required this.timedOut});

  /// -1 after a timeout.
  final int exitCode;
  final bool timedOut;

  @override
  String toString() => 'WaitResult(exitCode: $exitCode, timedOut: $timedOut)';
}

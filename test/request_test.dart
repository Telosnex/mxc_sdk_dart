import 'package:mxc_sdk_dart/mxc_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> prepare(ContainerRequest request) =>
      prepareContainerRequest(request, platform: 'windows');

  test('the request of sandbox-runtime maps to the one-shot contract', () {
    final json = prepare(
      const ContainerRequest(
        command: r'C:\Windows\System32\cmd.exe /d /s /c "echo hi"',
        containerName: 'fixed',
        filesystem: FilesystemPolicy(
          readwritePaths: [r'C:\repo'],
          readonlyPaths: [r'C:\'],
          deniedPaths: [r'C:\repo\.env'],
        ),
        network: NetworkPolicy(
          egress: NetworkEgressConfig(defaultAction: NetworkAction.deny),
          ingress: NetworkIngressConfig(
            defaultAction: NetworkAction.allow,
            hostLoopback: NetworkAction.allow,
          ),
          networkProxy: 'http://127.0.0.1:8080',
        ),
        ui: UiPolicy(disable: false),
        timeoutMs: 5000,
        workingDirectory: r'C:\repo',
        environment: {'PATH': r'C:\Windows', 'SKIP': null},
        inheritDefaultEnvironment: false,
      ),
    );
    expect(json, {
      'version': '1.0.0',
      'containerId': 'fixed',
      'containment': 'process',
      'lifecycle': {'destroyOnExit': true, 'preservePolicy': false},
      'process': {
        'commandLine': r'C:\Windows\System32\cmd.exe /d /s /c "echo hi"',
        'timeout': 5000,
        'cwd': r'C:\repo',
        'env': [r'PATH=C:\Windows'],
      },
      'filesystem': {
        'readwritePaths': [r'C:\repo'],
        'readonlyPaths': [r'C:\'],
        'deniedPaths': [r'C:\repo\.env'],
      },
      'network': {
        'egress': {'default': 'deny'},
        'ingress': {'default': 'allow', 'hostLoopback': 'allow'},
      },
      'runtimeConfig': {'networkProxy': 'http://127.0.0.1:8080'},
      'ui': {'disable': false, 'clipboard': 'none', 'injection': false},
    });
  });

  test('a minimal request gets defaults and a random container name', () {
    final a = prepare(const ContainerRequest(command: 'x'));
    final b = prepare(const ContainerRequest(command: 'x'));
    expect(a['containerId'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(a['containerId'], isNot(b['containerId']));
    expect(a['process'], {'commandLine': 'x', 'timeout': 0});
    expect(a.containsKey('network'), isFalse);
    expect(a.containsKey('ui'), isFalse);
    expect(a.containsKey('processContainer'), isFalse);
  });

  group('processcontainer', () {
    test('a directional network policy drops the derived capabilities', () {
      final json = prepare(
        const ContainerRequest(
          command: 'x',
          containment: ProcessContainerContainment(),
          network: NetworkPolicy(
            egress: NetworkEgressConfig(defaultAction: NetworkAction.allow),
          ),
        ),
      );
      expect(json['processContainer'], {
        'leastPrivilege': false,
        'capabilities': <String>[],
      });
    });

    test('caller settings are kept', () {
      final json = prepare(
        const ContainerRequest(
          command: 'x',
          containment: ProcessContainerContainment(
            ProcessContainerConfig(
              capabilities: ['registryRead'],
              learningMode: true,
              enumeratePaths: [r'C:\Users'],
              allowedProxyPeer: 'peer',
              ui: BaseProcessUiConfig(ime: true),
            ),
          ),
        ),
      );
      expect(json['processContainer'], {
        'leastPrivilege': false,
        'capabilities': ['registryRead'],
        'learningMode': true,
        'filesystem': {
          'enumeratePaths': [r'C:\Users'],
        },
        'network': {'allowedProxyPeer': 'peer'},
        'ui': {
          'isolation': 'container',
          'desktopSystemControl': false,
          'systemSettings': 'none',
          'ime': true,
        },
      });
    });

    test('enumeratePaths needs Windows', () {
      expect(
        () => prepareContainerRequest(
          const ContainerRequest(
            command: 'x',
            containment: ProcessContainerContainment(
              ProcessContainerConfig(enumeratePaths: ['/x']),
            ),
          ),
          platform: 'macos',
        ),
        throwsA(isA<MxcError>()),
      );
    });
  });

  group('malformed requests', () {
    void expectMalformed(ContainerRequest request) => expect(
      () => prepare(request),
      throwsA(
        isA<MxcError>().having(
          (e) => e.code,
          'code',
          MxcErrorCode.malformedRequest,
        ),
      ),
    );

    test('empty command', () {
      expectMalformed(const ContainerRequest(command: ''));
    });

    test('environment name with =', () {
      expectMalformed(
        const ContainerRequest(command: 'x', environment: {'A=B': 'c'}),
      );
    });

    test('timeout out of range', () {
      expectMalformed(const ContainerRequest(command: 'x', timeoutMs: -1));
    });

    test('port range', () {
      expectMalformed(
        const ContainerRequest(
          command: 'x',
          network: NetworkPolicy(
            egress: NetworkEgressConfig(
              allow: [
                NetworkRuleConfig(
                  ports: [NetworkPortConfig(port: 80, endPort: 79)],
                ),
              ],
            ),
          ),
        ),
      );
    });
  });
}

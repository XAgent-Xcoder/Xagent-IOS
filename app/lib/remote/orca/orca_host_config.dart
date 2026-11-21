/// One saved Orca host. The endpoint lives in this config (persisted as JSON
/// in SharedPreferences); the pairing code is a secret and lives in the
/// [SecretStore] under [OrcaSecrets] keys, never in this config.
class OrcaHostConfig {
  const OrcaHostConfig({
    required this.id,
    required this.name,
    required this.endpoint,
    this.workingDirectory,
  });

  /// Stable id (`orca-<hex>`); also the secret-store namespace.
  final String id;

  /// What the person calls it ("我的电脑", "家里的 Mac").
  final String name;

  /// The Orca host's WebSocket endpoint, e.g. `ws://192.168.1.10:6769`.
  final String endpoint;

  /// Default worktree selector for new conversations on this host.
  /// Null: the host picks its own default.
  final String? workingDirectory;

  /// A fingerprint that identifies a connection-worthy change. Renames and
  /// cwd edits do not reconnect; endpoint changes do.
  String get connectionKey => '$endpoint';

  bool get isOrca => true;

  OrcaHostConfig copyWith({
    String? name,
    String? endpoint,
    String? Function()? workingDirectory,
  }) => OrcaHostConfig(
    id: id,
    name: name ?? this.name,
    endpoint: endpoint ?? this.endpoint,
    workingDirectory: workingDirectory != null
        ? workingDirectory()
        : this.workingDirectory,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint,
    if (workingDirectory != null) 'workingDirectory': workingDirectory,
  };

  static OrcaHostConfig fromJson(Map<String, dynamic> json) {
    final rawEndpoint = json['endpoint'];
    final rawId = json['id'];
    if (rawEndpoint is! String || rawEndpoint.isEmpty) {
      throw const FormatException('OrcaHostConfig requires a non-empty endpoint');
    }
    return OrcaHostConfig(
      id: rawId is String && rawId.isNotEmpty ? rawId : 'orca-0',
      name: json['name'] is String ? json['name'] as String : 'Orca',
      endpoint: rawEndpoint,
      workingDirectory: json['workingDirectory'] is String
          ? json['workingDirectory'] as String
          : null,
    );
  }
}

/// Secret-store keys for Orca hosts. The pairing code is the only secret; it
/// is the host's offer that the app exchanges for a legacy E2EE channel.
class OrcaSecrets {
  const OrcaSecrets({this.pairingCode});

  final String? pairingCode;

  /// The pairing-code key: `orca.<hostId>.pairingCode`.
  static String pairingCodeKey(String hostId) => 'orca.$hostId.pairingCode';
}

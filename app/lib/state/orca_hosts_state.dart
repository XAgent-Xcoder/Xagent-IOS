import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../remote/orca/orca_host_config.dart';
import '../remote/secret_store.dart';
import 'hosts_state.dart';
import 'read_list_epoch.dart';

/// Saved Orca hosts: configs in SharedPreferences (no secrets), the pairing
/// code in the [SecretStore]. A separate provider from the SSH hosts so the
/// existing SSH controller and its tests are untouched.
class OrcaHostsState {
  const OrcaHostsState({this.orca = const [], this.loaded = false});

  final List<OrcaHostConfig> orca;
  final bool loaded;

  OrcaHostConfig? orcaById(String id) {
    for (final h in orca) {
      if (h.id == id) return h;
    }
    return null;
  }
}

class OrcaHostsController extends Notifier<OrcaHostsState> {
  static const prefsKey = 'remote_orca_hosts';

  SecretStore get _secrets => ref.read(secretStoreProvider);
  late Future<void> _loaded;

  @override
  OrcaHostsState build() {
    _loaded = _load();
    return const OrcaHostsState();
  }

  /// Completes once the saved list has been read.
  Future<void> get ready => _loaded;

  Future<void> _load() async {
    var hosts = const <OrcaHostConfig>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw != null) {
        final list = jsonDecode(raw);
        if (list is List) {
          hosts = list
              .map((e) => OrcaHostConfig.fromJson((e as Map).cast<String, dynamic>()))
              .toList();
        }
      }
    } catch (_) {
      // No preferences backend (tests) or a corrupt entry: start empty.
    }
    state = OrcaHostsState(orca: hosts, loaded: true);
  }

  Future<bool> _persist(List<OrcaHostConfig> hosts) async {
    state = OrcaHostsState(orca: List.unmodifiable(hosts), loaded: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(
        prefsKey,
        jsonEncode([for (final h in hosts) h.toJson()]),
      );
    } catch (_) {
      return false;
    }
  }

  /// Adds or replaces [config]. Stores [secrets.pairingCode] and drops any
  /// stale one. Returns the preferences write result.
  Future<bool> saveOrca(OrcaHostConfig config, {OrcaSecrets? secrets}) async {
    await _loaded;
    ref.read(readListCredentialEpochProvider.notifier).advance();
    if (secrets != null) {
      await _writePairingCode(config, secrets);
    }
    final hosts = [...state.orca];
    final index = hosts.indexWhere((h) => h.id == config.id);
    if (index >= 0) {
      hosts[index] = config;
    } else {
      hosts.add(config);
    }
    return _persist(hosts);
  }

  Future<void> _writePairingCode(OrcaHostConfig config, OrcaSecrets secrets) async {
    final key = OrcaSecrets.pairingCodeKey(config.id);
    if (secrets.pairingCode == null || secrets.pairingCode!.isEmpty) {
      await _secrets.delete(key);
    } else {
      await _secrets.write(key, secrets.pairingCode!);
    }
  }

  Future<String?> loadPairingCode(String id) async {
    try {
      return await _secrets.read(OrcaSecrets.pairingCodeKey(id));
    } catch (_) {
      return null;
    }
  }

  /// Removes the host and its pairing code; switches back to 本机 if it was
  /// active.
  Future<void> removeOrca(String id) async {
    await _loaded;
    await _persist([...state.orca.where((h) => h.id != id)]);
    try {
      await _secrets.delete(OrcaSecrets.pairingCodeKey(id));
    } catch (_) {}
    unawaited(ref.read(activeHostProvider.notifier).forget((h) => h == HostRef.orca(id)));
  }
}

final orcaHostsProvider = NotifierProvider<OrcaHostsController, OrcaHostsState>(
  OrcaHostsController.new,
);

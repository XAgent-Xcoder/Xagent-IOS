/// Where the model catalog's data came from.
enum ModelCatalogOrigin { liveSession, probe, unknown, unavailable }

/// A single selectable model on the host.
class ModelOption {
  const ModelOption({
    required this.key,
    required this.label,
    this.isDefault = false,
    this.reasoningEffort,
  });

  /// The option key used with `agentSession.setOption` to select this model.
  final String key;

  /// Display label.
  final String label;

  /// Whether this is the host's default selection.
  final bool isDefault;

  /// Reasoning effort associated with the model, when reported.
  final String? reasoningEffort;
}

/// The model catalog read from `agentSession.modelCatalog`.
class ModelCatalog {
  const ModelCatalog({
    required this.origin,
    this.models = const [],
    this.fetchedAt,
    this.waitExpired = false,
    this.unavailableReason,
  });

  final ModelCatalogOrigin origin;
  final List<ModelOption> models;

  /// When the catalog was fetched (epoch ms).
  final int? fetchedAt;

  /// True when the host reported it was still waiting for a live listing and
  /// the wait expired before one arrived.
  final bool waitExpired;

  /// A reason string when the catalog is unavailable.
  final String? unavailableReason;

  /// Parses an `AgentSessionModelCatalogResult` wire object.
  factory ModelCatalog.fromResult(Map<String, dynamic> result) {
    if (result['unavailable'] == true) {
      return ModelCatalog(
        origin: ModelCatalogOrigin.unavailable,
        unavailableReason: result['unavailableReason'] is String
            ? result['unavailableReason'] as String
            : null,
      );
    }
    final origin = switch (result['origin']) {
      'live-session' => ModelCatalogOrigin.liveSession,
      'probe' => ModelCatalogOrigin.probe,
      _ => ModelCatalogOrigin.unknown,
    };
    final models = <ModelOption>[];
    if (result['models'] is List) {
      for (final raw in result['models'] as List) {
        if (raw is Map<String, dynamic>) {
          final key = raw['key'] is String ? raw['key'] as String : '';
          if (key.isEmpty) continue;
          models.add(ModelOption(
            key: key,
            label: raw['label'] is String ? raw['label'] as String : key,
            isDefault: raw['defaultSelection'] == true,
            reasoningEffort: raw['reasoningEffort'] is String
                ? raw['reasoningEffort'] as String
                : null,
          ));
        }
      }
    }
    return ModelCatalog(
      origin: origin,
      models: models,
      fetchedAt: result['fetchedAt'] is int ? result['fetchedAt'] as int : null,
      waitExpired: result['waitExpired'] == true,
    );
  }
}

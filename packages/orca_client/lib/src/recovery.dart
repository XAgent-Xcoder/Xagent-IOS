import 'backend_types.dart';
import 'history_page.dart';
import 'subscribe_event.dart';

/// The recovery state machine of design doc §5.6: after a disconnect, network
/// switch, or app backgrounding, the client re-subscribes by cursor and the
/// host replays a `snapshot` then `batch` frames. This class folds those
/// frames into local state with the rules the design doc fixes:
///
/// - a `snapshot` **overwrites** local item state (the host's authoritative
///   full page, not an append);
/// - items **dedupe by itemId** so a batch that re-delivers an item the
///   snapshot already carried is not duplicated;
/// - a `reset` frame carrying a **higher fence** is the host-restart signal:
///   [onReattach] fires so the caller re-authenticates and re-negotiates
///   capabilities rather than blindly continuing on a stale fence;
/// - submission dispatch states (`pending` / `accepted`) are surfaced in
///   [dispatchStates] so the UI shows "still waiting" or "failed" — never
///   swallowed;
/// - a `snapshot` alone does **not** mean recovery is complete: [isRecovered]
///   is only true once the subscription reaches its `end` frame.
class SessionRecovery {
  /// Invoked with the host's new fence when a reset frame shows the host
  /// restarted (the fence jumped). Null until set.
  void Function(int fence)? onReattach;

  /// Invoked once when the subscription reaches its `end` frame. Null until
  /// set.
  void Function()? onRecovered;

  final Set<String> _itemIds = {};
  final List<String> _orderedItemIds = [];
  final Map<String, DispatchState> _dispatch = {};
  int? _fence;
  bool _recovered = false;

  /// Item IDs seen so far, in first-seen order (deduped).
  List<String> get itemIds => List.unmodifiable(_orderedItemIds);

  /// The current host fence, if one has been reported.
  int? get fence => _fence;

  /// Dispatch state of each client submission the host has reported.
  Map<String, DispatchState> get dispatchStates => Map.unmodifiable(_dispatch);

  /// True once the subscription has reached its `end` frame.
  bool get isRecovered => _recovered;

  /// Seeds the recovery with the initial history items so that the first
  /// `batch` frame that re-delivers an already-seen item is deduped.
  /// [fence] is the host-reported fence the initial history page was read
  /// under; it becomes the baseline for fence-jump detection.
  /// Called once by [MobileChatBackend.openConversation] before subscribing.
  void seed(List<HistoryItem> initialItems, {int? fence}) {
    for (final item in initialItems) {
      if (!_itemIds.contains(item.id)) {
        _itemIds.add(item.id);
        _orderedItemIds.add(item.id);
      }
    }
    if (fence != null) _fence = fence;
  }

  /// Folds one subscribe frame into local state.
  void process(SubscribeEvent event) {
    switch (event.type) {
      case SubscribeEventType.snapshot:
      case SubscribeEventType.reset:
        final previous = _fence;
        _itemIds.clear();
        _orderedItemIds.clear();
        _dispatch.clear();
        for (final item in event.items) {
          _itemIds.add(item.id);
          _orderedItemIds.add(item.id);
        }
        _fence = event.fence;
        if (event.type == SubscribeEventType.reset &&
            event.fence != null &&
            previous != null &&
            event.fence! > previous) {
          onReattach?.call(event.fence!);
        }
      case SubscribeEventType.batch:
        for (final item in event.items) {
          if (!_itemIds.contains(item.id)) {
            _itemIds.add(item.id);
            _orderedItemIds.add(item.id);
          }
        }
        if (event.fence != null) _fence = event.fence;
        _recordDispatch(event);
      case SubscribeEventType.end:
        if (!_recovered) {
          _recovered = true;
          onRecovered?.call();
        }
    }
  }

  void _recordDispatch(SubscribeEvent event) {
    for (final submission in event.submissions) {
      final id = submission['clientMessageId'] as String?;
      if (id == null) continue;
      _dispatch[id] = submission['state'] == 'accepted'
          ? DispatchState.accepted
          : DispatchState.pending;
    }
  }

  /// Resets the local state (a fresh session or a host switch).
  void reset() {
    _itemIds.clear();
    _orderedItemIds.clear();
    _dispatch.clear();
    _fence = null;
    _recovered = false;
  }
}

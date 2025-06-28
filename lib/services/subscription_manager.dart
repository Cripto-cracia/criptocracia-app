import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:dart_nostr/dart_nostr.dart' as dart_nostr;

typedef EventHandler = void Function(dynamic event);

class _SubscriptionPool {
  final String filterId;
  final dart_nostr.NostrFilter filter;
  final StreamSubscription subscription;
  final Set<String> handlerIds = {};
  final Map<String, EventHandler> handlers = {};

  _SubscriptionPool({
    required this.filterId, 
    required this.filter, 
    required this.subscription,
  });

  void addHandler(String handlerId, EventHandler handler) {
    handlerIds.add(handlerId);
    handlers[handlerId] = handler;
  }

  void removeHandler(String handlerId) {
    handlerIds.remove(handlerId);
    handlers.remove(handlerId);
  }

  bool get isEmpty => handlerIds.isEmpty;

  void routeEvent(dynamic event) {
    for (final handler in handlers.values) {
      try {
        handler(event);
      } catch (e) {
        debugPrint('⚠️ Handler error: $e');
      }
    }
  }
}

class SubscriptionManager {
  static SubscriptionManager? _instance;
  static SubscriptionManager get instance => _instance ??= SubscriptionManager._();

  final Map<String, _SubscriptionPool> _pools = {};
  dart_nostr.Nostr? _nostr;
  int _handlerCounter = 0;

  SubscriptionManager._();

  void initialize(dart_nostr.Nostr nostr) {
    _nostr = nostr;
  }

  String _generateFilterId(dart_nostr.NostrFilter filter) {
    final data = {
      'kinds': filter.kinds,
      'authors': filter.authors,
      'p': filter.p,
      'e': filter.e,
      'limit': filter.limit,
      'since': filter.since?.millisecondsSinceEpoch,
      'until': filter.until?.millisecondsSinceEpoch,
    };
    final json = jsonEncode(data);
    return sha256.convert(utf8.encode(json)).toString().substring(0, 16);
  }

  String subscribe({
    required dart_nostr.NostrFilter filter,
    required EventHandler onEvent,
  }) {
    if (_nostr == null) throw StateError('Not initialized');

    final filterId = _generateFilterId(filter);
    final handlerId = 'handler_${++_handlerCounter}';

    final pool = _pools[filterId];
    if (pool != null) {
      // Reuse existing subscription
      pool.addHandler(handlerId, onEvent);
      debugPrint('🔄 Reusing subscription $filterId for handler $handlerId');
    } else {
      // Create new subscription
      final request = dart_nostr.NostrRequest(filters: [filter]);
      final stream = _nostr!.services.relays.startEventsSubscription(request: request);
      
      final subscription = stream.stream.listen(
        (event) => _pools[filterId]?.routeEvent(event),
        onError: (e) => debugPrint('❌ Subscription error: $e'),
      );

      final newPool = _SubscriptionPool(
        filterId: filterId,
        filter: filter,
        subscription: subscription,
      );
      newPool.addHandler(handlerId, onEvent);
      _pools[filterId] = newPool;
      
      debugPrint('🆕 Created subscription $filterId for handler $handlerId');
    }

    return handlerId;
  }

  void unsubscribe(String handlerId) {
    for (final entry in _pools.entries) {
      final pool = entry.value;
      if (pool.handlerIds.contains(handlerId)) {
        pool.removeHandler(handlerId);
        
        if (pool.isEmpty) {
          pool.subscription.cancel();
          _pools.remove(entry.key);
          debugPrint('🗑️ Destroyed subscription ${entry.key}');
        } else {
          debugPrint('🔌 Removed handler $handlerId from ${entry.key}');
        }
        return;
      }
    }
  }

  Map<String, dynamic> getStats() {
    return {
      'active_subscriptions': _pools.length,
      'total_handlers': _pools.values.fold(0, (sum, pool) => sum + pool.handlerIds.length),
      'pools': _pools.map((id, pool) => MapEntry(id, {
        'filter_id': id,
        'handler_count': pool.handlerIds.length,
        'kinds': pool.filter.kinds,
      })),
    };
  }

  void dispose() {
    for (final pool in _pools.values) {
      pool.subscription.cancel();
    }
    _pools.clear();
    debugPrint('🧹 SubscriptionManager disposed');
  }
}
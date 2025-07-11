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
    debugPrint('🎯 Routing event to ${handlers.length} handlers');
    debugPrint('   Event ID: ${event.id}');
    debugPrint('   Event kind: ${event.kind}');
    
    for (final entry in handlers.entries) {
      final handlerId = entry.key;
      final handler = entry.value;
      try {
        debugPrint('📬 Calling handler $handlerId');
        handler(event);
        debugPrint('✅ Handler $handlerId completed successfully');
      } catch (e) {
        debugPrint('⚠️ Handler $handlerId error: $e');
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

    debugPrint('🔗 SubscriptionManager: Starting subscription');
    debugPrint('   Filter ID: $filterId');
    debugPrint('   Handler ID: $handlerId');
    debugPrint('   Filter kinds: ${filter.kinds}');
    debugPrint('   Filter p: ${filter.p}');

    final pool = _pools[filterId];
    if (pool != null) {
      // Reuse existing subscription
      pool.addHandler(handlerId, onEvent);
      debugPrint('🔄 Reusing subscription $filterId for handler $handlerId');
      debugPrint('   Pool now has ${pool.handlerIds.length} handlers');
    } else {
      // Create new subscription
      debugPrint('🆕 Creating new subscription for $filterId');
      final request = dart_nostr.NostrRequest(filters: [filter]);
      final stream = _nostr!.services.relays.startEventsSubscription(request: request);
      
      final subscription = stream.stream.listen(
        (event) {
          debugPrint('📥 SubscriptionManager: Received event for filter $filterId');
          debugPrint('   Event ID: ${event.id}');
          debugPrint('   Event kind: ${event.kind}');
          debugPrint('   Event pubkey: ${event.pubkey}');
          debugPrint('   Event tags: ${event.tags}');
          debugPrint('   Routing to ${_pools[filterId]?.handlerIds.length ?? 0} handlers');
          _pools[filterId]?.routeEvent(event);
        },
        onError: (e) {
          debugPrint('❌ Subscription error for $filterId: $e');
        },
        onDone: () {
          debugPrint('🔚 Subscription completed for $filterId');
        },
      );

      final newPool = _SubscriptionPool(
        filterId: filterId,
        filter: filter,
        subscription: subscription,
      );
      newPool.addHandler(handlerId, onEvent);
      _pools[filterId] = newPool;
      
      debugPrint('🆕 Created subscription $filterId for handler $handlerId');
      debugPrint('   Total active pools: ${_pools.length}');
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
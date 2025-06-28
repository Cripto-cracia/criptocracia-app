/// NostrEvent model representing a Nostr protocol event
/// Used for handling elections and election results in the Criptocracia voting system
class NostrEvent {
  /// Event ID (hex string)
  final String id;
  
  /// Public key of the event author (hex string)
  final String pubkey;
  
  /// Unix timestamp when the event was created (seconds since epoch)
  final int createdAt;
  
  /// Event kind (number indicating event type)
  final int kind;
  
  /// Event tags (array of arrays of strings)
  final List<List<String>> tags;
  
  /// Event content (JSON string or plain text)
  final String content;
  
  /// Event signature (hex string)
  final String sig;

  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  /// Create NostrEvent from JSON map
  factory NostrEvent.fromJson(Map<String, dynamic> json) {
    return NostrEvent(
      id: json['id'] as String? ?? '',
      pubkey: json['pubkey'] as String? ?? '',
      createdAt: json['created_at'] as int? ?? 0,
      kind: json['kind'] as int? ?? 0,
      tags: (json['tags'] as List<dynamic>?)
          ?.map((tag) => (tag as List<dynamic>)
              .map((e) => e.toString())
              .toList())
          .toList() ?? [],
      content: json['content'] as String? ?? '',
      sig: json['sig'] as String? ?? '',
    );
  }

  /// Convert NostrEvent to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pubkey': pubkey,
      'created_at': createdAt,
      'kind': kind,
      'tags': tags,
      'content': content,
      'sig': sig,
    };
  }

  /// Get DateTime representation of createdAt timestamp
  DateTime get createdAtDateTime => DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

  /// Check if this is an election event (kind 35000)
  bool get isElectionEvent => kind == 35000;

  /// Check if this is an election results event (kind 35001)
  bool get isElectionResultsEvent => kind == 35001;

  /// Get the 'd' tag value (used for election IDs in parameterized replaceable events)
  String? get dTagValue {
    try {
      final dTag = tags.firstWhere(
        (tag) => tag.isNotEmpty && tag[0] == 'd',
      );
      return dTag.length >= 2 ? dTag[1] : null;
    } catch (e) {
      return null;
    }
  }

  @override
  String toString() {
    return 'NostrEvent(id: $id, kind: $kind, pubkey: ${pubkey.substring(0, 8)}..., createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NostrEvent &&
        other.id == id &&
        other.pubkey == pubkey &&
        other.createdAt == createdAt &&
        other.kind == kind &&
        other.content == content &&
        other.sig == sig;
  }

  @override
  int get hashCode {
    return Object.hash(id, pubkey, createdAt, kind, content, sig);
  }

  /// Create a copy of this event with optional field updates
  NostrEvent copyWith({
    String? id,
    String? pubkey,
    int? createdAt,
    int? kind,
    List<List<String>>? tags,
    String? content,
    String? sig,
  }) {
    return NostrEvent(
      id: id ?? this.id,
      pubkey: pubkey ?? this.pubkey,
      createdAt: createdAt ?? this.createdAt,
      kind: kind ?? this.kind,
      tags: tags ?? this.tags,
      content: content ?? this.content,
      sig: sig ?? this.sig,
    );
  }
}
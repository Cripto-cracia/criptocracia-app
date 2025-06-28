import 'dart:convert';

/// Message model for Nostr communication in Criptocracia voting protocol
/// Represents the JSON payload sent/received in Gift Wrap events
class Message {
  /// Election ID
  final String id;
  
  /// Message kind: 1 = Token request/response, 2 = Vote, 3 = Error
  final int kind;
  
  /// Base64 encoded payload (blind signature, vote data, etc.)
  final String payload;

  const Message({
    required this.id,
    required this.kind,
    required this.payload,
  });

  /// Create Message from JSON string
  factory Message.fromJson(String jsonString) {
    try {
      final Map<String, dynamic> json = jsonDecode(jsonString);
      return Message.fromMap(json);
    } catch (e) {
      throw FormatException('Invalid JSON format for Message: $e');
    }
  }

  /// Create Message from Map
  factory Message.fromMap(Map<String, dynamic> json) {
    // Validate required fields
    if (!json.containsKey('id')) {
      throw FormatException('Missing required field: id');
    }
    if (!json.containsKey('kind')) {
      throw FormatException('Missing required field: kind');
    }
    if (!json.containsKey('payload')) {
      throw FormatException('Missing required field: payload');
    }

    // Validate field types
    final id = json['id'];
    if (id is! String) {
      throw FormatException('Field "id" must be a string, got: ${id.runtimeType}');
    }

    final kind = json['kind'];
    if (kind is! int) {
      throw FormatException('Field "kind" must be an integer, got: ${kind.runtimeType}');
    }

    final payload = json['payload'];
    if (payload is! String) {
      throw FormatException('Field "payload" must be a string, got: ${payload.runtimeType}');
    }

    return Message(
      id: id,
      kind: kind,
      payload: payload,
    );
  }

  /// Convert Message to Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'kind': kind,
      'payload': payload,
    };
  }

  /// Convert Message to JSON string
  String toJson() {
    return jsonEncode(toMap());
  }

  /// Validate message format and content
  bool isValid() {
    try {
      // Check basic field presence and types
      if (id.isEmpty) return false;
      if (kind < 1 || kind > 3) return false; // Support kinds 1, 2, and 3
      if (payload.isEmpty) return false;

      // Validate payload format (base64 for kinds 1&2, any text for kind 3)
      if (kind == 3) {
        // Error messages can be plain text or base64, both are valid
        return true;
      } else {
        // Token and vote messages must be valid base64
        try {
          base64.decode(payload);
        } catch (e) {
          return false; // Invalid base64
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get message type description
  String get kindDescription {
    switch (kind) {
      case 1:
        return 'Token Request/Response';
      case 2:
        return 'Vote';
      case 3:
        return 'Error';
      default:
        return 'Unknown';
    }
  }

  /// Check if this is a token request/response message
  bool get isTokenMessage => kind == 1;

  /// Check if this is a vote message
  bool get isVoteMessage => kind == 2;

  /// Check if this is an error message
  bool get isErrorMessage => kind == 3;

  /// Get error message content (for kind 3 messages)
  String? get errorContent {
    if (!isErrorMessage) return null;
    try {
      // For error messages, payload contains the error text (may not be base64)
      // Try to decode as base64 first, if that fails, use as plain text
      try {
        final decoded = base64.decode(payload);
        return utf8.decode(decoded);
      } catch (e) {
        // If base64 decode fails, treat as plain text
        return payload;
      }
    } catch (e) {
      return null;
    }
  }

  @override
  String toString() {
    return 'Message(id: $id, kind: $kind ($kindDescription), payload: ${payload.length} chars)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Message &&
        other.id == id &&
        other.kind == kind &&
        other.payload == payload;
  }

  @override
  int get hashCode {
    return Object.hash(id, kind, payload);
  }

  /// Create a copy of this message with optional field updates
  Message copyWith({
    String? id,
    int? kind,
    String? payload,
  }) {
    return Message(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      payload: payload ?? this.payload,
    );
  }
}
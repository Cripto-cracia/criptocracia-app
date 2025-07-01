class RelayStatus {
  final String url;
  final bool isConnected;
  final DateTime? lastSeen;
  final String? error;
  final int? latencyMs;

  const RelayStatus({
    required this.url,
    required this.isConnected,
    this.lastSeen,
    this.error,
    this.latencyMs,
  });

  RelayStatus copyWith({
    String? url,
    bool? isConnected,
    DateTime? lastSeen,
    String? error,
    int? latencyMs,
  }) {
    return RelayStatus(
      url: url ?? this.url,
      isConnected: isConnected ?? this.isConnected,
      lastSeen: lastSeen ?? this.lastSeen,
      error: error ?? this.error,
      latencyMs: latencyMs ?? this.latencyMs,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RelayStatus &&
        other.url == url &&
        other.isConnected == isConnected &&
        other.lastSeen == lastSeen &&
        other.error == error &&
        other.latencyMs == latencyMs;
  }

  @override
  int get hashCode {
    return url.hashCode ^
        isConnected.hashCode ^
        lastSeen.hashCode ^
        error.hashCode ^
        latencyMs.hashCode;
  }

  @override
  String toString() {
    return 'RelayStatus(url: $url, isConnected: $isConnected, lastSeen: $lastSeen, error: $error, latencyMs: $latencyMs)';
  }
}
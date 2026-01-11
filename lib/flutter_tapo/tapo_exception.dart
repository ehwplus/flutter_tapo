class TapoApiException implements Exception {
  const TapoApiException(this.code, this.message, {this.payload});

  final int code;
  final String message;
  final Map<String, dynamic>? payload;

  @override
  String toString() {
    return 'TapoApiException(code: $code, message: $message)';
  }
}

class TapoProtocolException implements Exception {
  const TapoProtocolException(this.message);

  final String message;

  @override
  String toString() {
    return 'TapoProtocolException(message: $message)';
  }
}

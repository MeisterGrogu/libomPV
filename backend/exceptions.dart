class FetchingError implements Exception {
  final String message;
  final int? statusCode;

  FetchingError(this.message, {this.statusCode});

  @override
  String toString() {
    return "$message (Statuscode: $statusCode)";
  }
}

class InvalidCredentialsError extends FetchingError {
  InvalidCredentialsError(String message, {int? statusCode})
    : super(message, statusCode: statusCode);
}

class XMLParsingError implements Exception {
  final String message;

  XMLParsingError(this.message);

  @override
  String toString() {
    return message;
  }
}

class XMLNotFound extends XMLParsingError {
  XMLNotFound(String message) : super(message);
}

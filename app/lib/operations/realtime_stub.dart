class OperationsRealtime {
  OperationsRealtime({
    required Uri baseUri,
    required String businessId,
    required Future<String> Function() token,
    required void Function() changed,
    required void Function(bool) connected,
  });
  void start() {}
  void close() {}
}

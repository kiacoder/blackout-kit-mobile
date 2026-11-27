/// Serializes camera mutations; queued work cannot run after shutdown.
class ScannerOperationQueue {
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  Future<void> run(Future<void> Function() operation) {
    if (_closed) return Future<void>.value();
    final result = _tail.then((_) async {
      if (!_closed) await operation();
    });
    // Report errors to the caller but do not poison later cleanup.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> close(Future<void> Function() dispose) {
    if (_closed) return _tail;
    _closed = true;
    _tail = _tail.then((_) => dispose());
    return _tail;
  }
}

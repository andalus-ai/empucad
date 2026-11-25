/// Linear undo/redo over immutable snapshots.
final class History<T> {
  History(T initial, {this.limit = 100}) : _present = initial;
  final int limit;
  final List<T> _past = [];
  final List<T> _future = [];
  T _present;

  T get present => _present;
  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;

  void push(T next) {
    if (identical(next, _present)) return;
    _past.add(_present);
    if (_past.length > limit) _past.removeAt(0);
    _present = next;
    _future.clear();
  }

  /// Replace the present without creating an undo step (e.g. while dragging).
  void replace(T next) => _present = next;

  void undo() {
    if (!canUndo) return;
    _future.add(_present);
    _present = _past.removeLast();
  }

  void redo() {
    if (!canRedo) return;
    _past.add(_present);
    _present = _future.removeLast();
  }
}

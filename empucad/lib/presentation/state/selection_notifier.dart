import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'editor_notifier.dart';

class SelectionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    // Drop ids that no longer exist after delete / undo / load.
    ref.listen(documentProvider, (_, doc) {
      final live = {for (final n in doc.allNodes) n.id};
      final kept = state.where(live.contains).toSet();
      if (kept.length != state.length) state = kept;
    });
    return const {};
  }

  void select(String? id, {bool additive = false}) {
    if (id == null) {
      if (!additive) state = const {};
      return;
    }
    if (!additive) {
      state = {id};
    } else {
      state = state.contains(id) ? (Set.of(state)..remove(id)) : {...state, id};
    }
  }

  void clear() => state = const {};
}

final selectionProvider = NotifierProvider<SelectionNotifier, Set<String>>(SelectionNotifier.new);

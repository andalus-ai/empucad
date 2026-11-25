import 'package:flutter_riverpod/flutter_riverpod.dart';

enum Workspace { design, cnc, laser }

class WorkspaceNotifier extends Notifier<Workspace> {
  @override
  Workspace build() => Workspace.design;
  void select(Workspace w) => state = w;
}

final workspaceProvider = NotifierProvider<WorkspaceNotifier, Workspace>(WorkspaceNotifier.new);

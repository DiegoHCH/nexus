import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/conversations_data_source.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Lo guardado en disco, con una conversación dentro.
class _Store implements ConversationsDataSource {
  Map<String, dynamic> data = {
    'items': [
      {'id': 'vieja', 'folderPath': '/repos/otro'},
    ],
    'focusedId': 'vieja',
  };

  @override
  Future<Map<String, dynamic>> read() async => data;

  @override
  Future<void> write(Map<String, dynamic> json) async => data = json;
}

class _Workspace extends WorkspaceController {
  _Workspace(this._value);
  Workspace _value;
  @override
  Workspace build() => _value;

  void permiso(FilePermission permission) {
    _value = _value.copyWith(permission: permission);
    state = _value;
  }
}

void main() {
  test(
    'cambiar el permiso no resucita una conversación que cerraste',
    () async {
      final workspace = _Workspace(
        Workspace(
          folders: [
            PairedFolder(path: '/repos/otro', modality: FolderModality.voice),
            PairedFolder(path: '/General', modality: FolderModality.voice),
          ],
          activePath: '/General',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          conversationsDataSourceProvider.overrideWithValue(_Store()),
          workspaceControllerProvider.overrideWith(() => workspace),
        ],
      );
      addTearDown(container.dispose);

      // Al arrancar se recupera lo guardado: eso sí se quiere.
      container.read(conversationsProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(conversationsProvider).items.length, 1);

      // Se cierra, y se cierra de verdad.
      await container.read(conversationsProvider.notifier).close('vieja');
      expect(container.read(conversationsProvider).items, isEmpty);

      // Y ahora lo que reportó el usuario: tocar el permiso repasa el espacio
      // de trabajo, y eso volvía a fusionar lo guardado — reapareciendo una
      // conversación cerrada, encima sobre otra carpeta.
      workspace.permiso(FilePermission.canEdit);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(conversationsProvider).items, isEmpty);
    },
  );
}

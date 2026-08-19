import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

class _Fixed extends WorkspaceController {
  _Fixed(this._value);
  final Workspace _value;
  @override
  Workspace build() => _value;
}

class _Folder extends ArtifactsFolder {
  _Folder(this._value);
  final String? _value;
  @override
  String? build() => _value;
}

/// Dónde nace una conversación cuando no hay ninguna abierta.
///
/// Se probó al encontrar que se abría siempre sobre `folders.first`: elegir
/// carpeta y ponerse a escribir empezaba en otra, y «Sin proyecto» se perdía
/// del todo porque la carpeta de documentos no está entre las emparejadas.
Future<String?> _resolve(
  WidgetTester tester, {
  required Workspace workspace,
  String? documentos,
}) async {
  String? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceControllerProvider.overrideWith(() => _Fixed(workspace)),
        artifactsFolderProvider.overrideWith(() => _Folder(documentos)),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          result = whereToStart(ref);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}

void main() {
  final proyecto = PairedFolder(
    path: '/repos/uno',
    modality: FolderModality.voice,
  );
  final otro = PairedFolder(path: '/repos/dos', modality: FolderModality.voice);

  testWidgets('manda la carpeta activa, no la primera de la lista', (
    tester,
  ) async {
    expect(
      await _resolve(
        tester,
        workspace: Workspace(
          folders: [proyecto, otro],
          activePath: '/repos/dos',
        ),
      ),
      '/repos/dos',
    );
  });

  testWidgets('«sin proyecto» sobrevive: no está entre las emparejadas', (
    tester,
  ) async {
    expect(
      await _resolve(
        tester,
        workspace: Workspace(
          folders: [proyecto],
          activePath: '/Users/x/Documentos',
        ),
        documentos: '/Users/x/Documentos',
      ),
      '/Users/x/Documentos',
    );
  });

  testWidgets('sin nada activo, la primera emparejada', (tester) async {
    expect(
      await _resolve(tester, workspace: Workspace(folders: [proyecto, otro])),
      '/repos/uno',
    );
  });

  // Pedir un mockup no exige tener un proyecto.
  testWidgets('sin ninguna emparejada, la carpeta de documentos', (
    tester,
  ) async {
    expect(
      await _resolve(
        tester,
        workspace: const Workspace(folders: []),
        documentos: '/Users/x/Documentos',
      ),
      '/Users/x/Documentos',
    );
  });

  testWidgets('sin nada de nada, no se inventa un sitio', (tester) async {
    expect(
      await _resolve(tester, workspace: const Workspace(folders: [])),
      isNull,
    );
  });
}

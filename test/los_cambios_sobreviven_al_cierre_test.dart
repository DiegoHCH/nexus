import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';

import 'support/screen_harness.dart';

/// Que el botón de ver cambios siga estando al día siguiente.
///
/// El fallo que esto arregla salió usándolo: los cambios vivían **solo en
/// memoria**, así que al cerrar la app y retomar la conversación el botón ya no
/// estaba — y lo que un encargo tocó es justo lo que uno vuelve a mirar al día
/// siguiente, no en el mismo minuto.

void main() {
  late Directory soporte;

  setUp(() => soporte = prepareScreenTest());
  tearDown(() => soporte.deleteSync(recursive: true));

  ConversationSummary fichaDe(ConversationRecord record) => ConversationSummary(
    id: record.id,
    folderPath: record.folderPath,
    startedAt: record.startedAt,
    title: 'da igual',
    turns: record.messages.length,
  );

  const diff = '''
diff --git a/lib/a.dart b/lib/a.dart
@@ -1,1 +1,1 @@
-vieja
+nueva
''';

  ConversationRecord conUnCambio(GitChanges cambios, {String? documento}) =>
      ConversationRecord(
        id: 'uno',
        folderPath: '/repo',
        startedAt: DateTime(2026, 8, 29),
        messages: [
          const ChatMessage(author: ChatAuthor.user, text: 'cambia algo'),
          ChatMessage(
            author: ChatAuthor.nexus,
            text: 'hecho',
            cambios: cambios,
            documento: documento,
          ),
        ],
      );

  test('lo que cambió un turno vuelve con la conversación', () async {
    const almacen = LocalConversationStore();
    final record = conUnCambio(
      const GitChanges(diff: diff, newFiles: ['lib/nuevo.dart']),
    );
    await almacen.save(record);

    final vuelta = await almacen.read(fichaDe(record));
    final respuesta = vuelta!.messages.last;

    expect(respuesta.cambios?.diff, diff);
    expect(respuesta.cambios?.newFiles, ['lib/nuevo.dart']);
    expect(respuesta.cambios?.fileCount, 2);
  });

  test('un turno que no tocó nada no guarda nada', () async {
    const almacen = LocalConversationStore();
    final record = ConversationRecord(
      id: 'uno',
      folderPath: '/repo',
      startedAt: DateTime(2026, 8, 29),
      messages: const [ChatMessage(author: ChatAuthor.nexus, text: 'hola')],
    );
    await almacen.save(record);

    final vuelta = await almacen.read(fichaDe(record));
    expect(vuelta!.messages.single.cambios, isNull);
  });

  // Un encargo grande deja cientos de kilobytes de diff. Guardarlos enteros
  // multiplicaría por diez el archivo que el historial lee para pintar su lista.
  group('el tope de lo que se guarda', () {
    test('un diff normal se guarda entero', () {
      final json = const GitChanges(diff: diff, newFiles: []).toJson();
      expect(json['diff'], diff);
      expect(json.containsKey('recortado'), isFalse);
    });

    test('uno enorme se recorta, y se dice', () {
      final gigante = StringBuffer();
      // Muchos archivos, para que haya por dónde cortar limpio.
      for (var i = 0; i < 4000; i++) {
        gigante.write(
          'diff --git a/f$i.dart b/f$i.dart\n@@ -1,1 +1,1 @@\n-a\n+b\n',
        );
      }
      final json = GitChanges(
        diff: gigante.toString(),
        newFiles: const [],
      ).toJson();

      expect(json['recortado'], isTrue);
      expect(
        (json['diff'] as String).length,
        lessThanOrEqualTo(GitChanges.maxGuardado),
      );
      // **Por archivos enteros**: cortar a mitad de un tramo produce algo que
      // ya no es un diff, y el visor lo pintaría torcido.
      expect(json['diff'], isNot(endsWith('@@ -1,1 +1,1 @@\n')));
      expect(jsonEncode(json), isNotEmpty);
    });
  });

  test('un documento que ya no está no deja un botón muerto', () async {
    const almacen = LocalConversationStore();
    final record = conUnCambio(
      const GitChanges(diff: diff, newFiles: []),
      documento: '${soporte.path}/se-borro.html',
    );
    await almacen.save(record);

    final vuelta = await almacen.read(fichaDe(record));
    expect(
      vuelta!.messages.last.documento,
      isNull,
      reason: 'un botón que no lleva a ningún sitio enseña a no pulsarlo',
    );
  });
}

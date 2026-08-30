import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/artifacts/domain/entities/artifact.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/assistant/presentation/widgets/attachment_strip.dart';
import 'package:nexus/features/assistant/presentation/widgets/chat_panel.dart';

/// Una imagen se enseña; no se anuncia.
///
/// Con el botón de siempre, lo que acababa de generarse era un nombre de
/// archivo: para saber si había salido bien había que abrirla. Se pinta con la
/// misma tira que los adjuntos porque es el mismo gesto por el otro lado — tú
/// le pasas una imagen al chat y la ves, él te devuelve una y también.
void main() {
  Widget conversacion(List<ChatMessage> mensajes) => ProviderScope(
    child: MaterialApp(
      theme: NexusTheme.dark(),
      builder: (context, child) =>
          StringsScope(strings: const NexusStringsEs(), child: child!),
      home: Scaffold(body: ChatPanel(messages: mensajes)),
    ),
  );

  testWidgets('la imagen que dejó el encargo sale con su miniatura', (
    tester,
  ) async {
    await tester.pumpWidget(
      conversacion(const [
        ChatMessage(
          author: ChatAuthor.nexus,
          text: 'Ahí tienes el zorro.',
          documento: '/Users/alguien/documentos/zorro.webp',
        ),
      ]),
    );
    await tester.pump();

    expect(find.byType(AttachmentStrip), findsOneWidget);
  });

  // Un documento que se lee no se mira: llenar la conversación de miniaturas de
  // markdown sería ruido, y para eso ya está el botón con su nombre.
  testWidgets('un documento de texto se queda en su botón', (tester) async {
    await tester.pumpWidget(
      conversacion(const [
        ChatMessage(
          author: ChatAuthor.nexus,
          text: 'Ahí tienes las notas.',
          documento: '/Users/alguien/documentos/notas.md',
        ),
      ]),
    );
    await tester.pump();

    expect(find.byType(AttachmentStrip), findsNothing);
  });

  group('qué cuenta como imagen', () {
    // `.webp` es lo que devuelven los Spaces de generación. Sin él, una imagen
    // recién hecha no contaba como documento: ni lista, ni botón, ni miniatura.
    test('webp también, que es lo que devuelven los modelos', () {
      expect(Artifact.isImage('/x/zorro.webp'), isTrue);
      expect(Artifact.isListable('/x/zorro.webp'), isTrue);
      expect(Artifact.isViewable('/x/zorro.webp'), isTrue);
    });

    test('lo que se abre pero no es una imagen, no lo es', () {
      for (final documento in [
        '/x/notas.md',
        '/x/mockup.html',
        '/x/hoja.pdf',
      ]) {
        expect(Artifact.isImage(documento), isFalse, reason: documento);
      }
    });
  });
}

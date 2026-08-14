import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/domain/usecases/attached_files.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/assistant/presentation/widgets/attachment_strip.dart';
import 'package:nexus/features/assistant/presentation/widgets/chat_panel.dart';

/// Lo que se le manda a Claude y lo que se le enseña a quien mira **son dos
/// cosas distintas**.
///
/// Antes eran el mismo texto: la instrucción llevaba «Archivos adjuntos:» y la
/// ruta absoluta detrás porque Claude las necesita para abrir el archivo, y la
/// conversación acababa enseñando `/Users/…/ESTAMPADO CAMISETA.ai` en vez del
/// archivo. Claude sigue recibiendo la ruta; la vista, la miniatura.
void main() {
  const adjunto = '/Users/alguien/General/ESTAMPADO CAMISETA.ai';

  test('la instrucción para Claude conserva la ruta entera', () {
    final instruccion = AttachedFiles.instruction(
      'este es el archivo .ai',
      const [adjunto],
      label: 'Archivos adjuntos:',
    );

    expect(instruccion, contains(adjunto));
    expect(instruccion, startsWith('este es el archivo .ai'));
  });

  testWidgets('pero la conversación enseña la miniatura, no la ruta', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NexusTheme.dark(),
        builder: (context, child) =>
            StringsScope(strings: const NexusStringsEs(), child: child!),
        home: const Scaffold(
          body: ChatPanel(
            messages: [
              ChatMessage(
                author: ChatAuthor.user,
                text: 'este es el archivo .ai',
                attachments: [adjunto],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AttachmentStrip), findsOneWidget);
    expect(find.textContaining('ESTAMPADO CAMISETA.ai'), findsWidgets);
    expect(
      find.textContaining('/Users/alguien/General/'),
      findsNothing,
      reason: 'la ruta absoluta vive en el tooltip, no en la conversación',
    );
    expect(find.text('este es el archivo .ai'), findsOneWidget);
  });

  testWidgets('sin ✕: aquí el mensaje ya salió', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NexusTheme.dark(),
        builder: (context, child) =>
            StringsScope(strings: const NexusStringsEs(), child: child!),
        home: const Scaffold(
          body: ChatPanel(
            messages: [
              ChatMessage(
                author: ChatAuthor.user,
                text: 'mira esto',
                attachments: [adjunto],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.close), findsNothing);
  });

  test('un mensaje que solo trae adjuntos no está vacío', () {
    // Soltar un archivo y dar a enviar es un gesto legítimo; tratarlo como
    // vacío lo borraría de la conversación.
    const soloAdjunto = ChatMessage(
      author: ChatAuthor.user,
      text: '',
      attachments: [adjunto],
    );
    expect(soloAdjunto.isEmpty, isFalse);
    expect(
      const ChatMessage(author: ChatAuthor.user, text: '   ').isEmpty,
      isTrue,
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/assistant/presentation/widgets/chat_panel.dart';

/// Copiar una respuesta entera del chat.
///
/// No se podía: se seleccionaba un párrafo y al arrastrar hasta el siguiente la
/// selección saltaba al nuevo y soltaba el anterior, así que una respuesta
/// larga había que copiarla a trozos. La causa no se ve mirando la pantalla —se
/// ve en el árbol—: `selectable: true` monta **un `SelectableText` por bloque
/// de markdown**, y cada isla cancela la de al lado.
///
/// Por eso esto se prueba contando islas y no simulando un arrastre: lo que hay
/// que impedir es que vuelva a aparecer una.
void main() {
  Widget conversacion(List<ChatMessage> mensajes) => MaterialApp(
    theme: NexusTheme.dark(),
    builder: (context, child) =>
        StringsScope(strings: const NexusStringsEs(), child: child!),
    home: Scaffold(body: ChatPanel(messages: mensajes)),
  );

  const dosParrafos = ChatMessage(
    author: ChatAuthor.nexus,
    text: 'Primer párrafo de la respuesta.\n\n'
        'Segundo párrafo, que antes no se dejaba seleccionar con el primero.\n\n'
        '- y una lista\n- con dos puntos\n',
  );

  testWidgets('toda la conversación es una sola selección', (tester) async {
    await tester.pumpWidget(
      conversacion(const [
        ChatMessage(author: ChatAuthor.user, text: 'cuéntame algo largo'),
        dosParrafos,
      ]),
    );
    await tester.pump();

    // Una, y por encima de la lista: envolviendo cada mensaje habría tantas
    // islas como turnos, que es el mismo problema una capa más arriba.
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SelectionArea),
        matching: find.byType(ListView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('y nadie dentro se queda con la suya', (tester) async {
    await tester.pumpWidget(
      conversacion(const [
        ChatMessage(author: ChatAuthor.user, text: 'cuéntame algo largo'),
        dosParrafos,
      ]),
    );
    await tester.pump();

    // Ni el markdown de la respuesta ni el texto de lo que escribiste: los dos
    // eran seleccionables por su cuenta, y arrastrar de uno a otro cortaba.
    expect(
      find.byType(SelectableText),
      findsNothing,
      reason: 'una isla propia vuelve a cortar el arrastre entre párrafos',
    );
  });
}

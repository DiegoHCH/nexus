import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/assistant/presentation/widgets/chat_panel.dart';

/// Correr el comando que la respuesta acaba de escribir.
///
/// 🔴 **Medido dos días seguidos sobre el mismo repo.** El asistente contestó
/// `git push -u origin fix/SU-601-…` y lo que se mandó fue `git push` a secas;
/// el día anterior, lo mismo con otra rama. Dos errores 128 distintos —una rama
/// sin upstream y otra con el upstream en `main`— por una sola causa: el
/// comando estaba escrito y había que retranscribirlo a mano.
void main() {
  const strings = NexusStringsEs();

  Widget conversacion(
    String texto, {
    void Function(String comando)? onCorrer,
  }) => MaterialApp(
    theme: NexusTheme.dark(),
    builder: (context, child) =>
        StringsScope(strings: const NexusStringsEs(), child: child!),
    home: Scaffold(
      body: ChatPanel(
        messages: [ChatMessage(author: ChatAuthor.nexus, text: texto)],
        onCorrer: onCorrer,
      ),
    ),
  );

  const conGit = 'Sube la rama con:\n\n```\ngit push -u origin HEAD\n```\n';

  testWidgets('el bloque que se puede correr trae su botón', (tester) async {
    await tester.pumpWidget(conversacion(conGit, onCorrer: (_) {}));
    await tester.pump();

    expect(find.text(strings.runThisCommand), findsOneWidget);
  });

  testWidgets('y manda el comando tal cual se ve, con su «!»', (tester) async {
    final mandados = <String>[];
    await tester.pumpWidget(conversacion(conGit, onCorrer: mandados.add));
    await tester.pump();

    await tester.tap(find.text(strings.runThisCommand));
    await tester.pump();

    expect(mandados, ['!git push -u origin HEAD']);
  });

  // 🔴 Un botón que a veces contesta «solo sé de git» enseña a no pulsarlo, y
  // entonces tampoco se pulsa el día que sí lleva a algún sitio.
  testWidgets('lo que no se sabe correr no lo trae', (tester) async {
    await tester.pumpWidget(
      conversacion(
        'Primero entra con:\n\n```\naws sso login --sso-session global66\n```\n',
        onCorrer: (_) {},
      ),
    );
    await tester.pump();

    expect(find.text(strings.runThisCommand), findsNothing);
  });

  testWidgets('un guion de varias líneas tampoco', (tester) async {
    await tester.pumpWidget(
      conversacion(
        '```\ngit add -A\ngit commit -m "x"\n```\n',
        onCorrer: (_) {},
      ),
    );
    await tester.pump();

    expect(find.text(strings.runThisCommand), findsNothing);
  });

  // El historial pinta los mismos mensajes y no tiene dónde correr nada: sin
  // callback, el bloque se queda como estaba.
  testWidgets('sin quien lo corra, no se ofrece', (tester) async {
    await tester.pumpWidget(conversacion(conGit));
    await tester.pump();

    expect(find.text(strings.runThisCommand), findsNothing);
  });
}

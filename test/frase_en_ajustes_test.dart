import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/remote/domain/write_phrase.dart';
import 'package:nexus/features/remote/presentation/pages/mobile_section.dart';
import 'package:nexus/features/remote/presentation/providers/write_phrase_providers.dart';

import 'support/screen_harness.dart';

// La fila de la frase, mirada.
//
// Lo que se vigila es lo que no se ve venir: que la frase **aparezca** en una
// pantalla que se comparte en capturas más de lo que parece, y que el mínimo se
// compruebe de verdad en vez de solo estar escrito en un texto de ayuda.
class _Memoria implements WritePhraseStore {
  _Memoria([this._guardada]);

  WritePhrase? _guardada;
  int borrados = 0;

  @override
  Future<WritePhrase?> read() async => _guardada;
  @override
  Future<void> write(WritePhrase phrase) async => _guardada = phrase;
  @override
  Future<void> clear() async {
    _guardada = null;
    borrados++;
  }
}

void main() {
  const es = NexusStringsEs();
  late Directory support;

  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  Future<ProviderContainer> abrir(WidgetTester tester, _Memoria store) async {
    late ProviderContainer container;
    await pumpScreen(
      tester,
      Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return const Scaffold(body: MobileSection());
        },
      ),
      overrides: [writePhraseStoreProvider.overrideWithValue(store)],
    );
    return container;
  }

  testWidgets('sin frase lo dice, y no como si fuera un error', (tester) async {
    await abrir(tester, _Memoria());
    expect(find.text(es.phraseMissing), findsOne);
    expect(find.text(es.phraseDefine), findsOne);
    // Y no ofrece quitar lo que no hay.
    expect(find.byKey(const ValueKey('quitar-la-frase')), findsNothing);
  });

  testWidgets('con frase definida dice que la hay, y nunca cuál', (tester) async {
    await abrir(tester, _Memoria(const WritePhrase('la-frase-de-verdad')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(es.phraseDefined), findsOne);
    expect(find.byKey(const ValueKey('quitar-la-frase')), findsOne);
    // Lo que importa: ni el valor ni un trozo suyo aparecen en ningún sitio de la
    // pantalla. Al contrario que el token, aquí no hay ni huella — el token hay que
    // copiarlo al teléfono alguna vez, la frase se teclea de memoria.
    expect(find.textContaining('la-frase'), findsNothing);
    expect(find.textContaining('verdad'), findsNothing);
  });

  testWidgets('una frase corta no se guarda, y lo dice al intentarlo', (
    tester,
  ) async {
    final store = _Memoria();
    await abrir(tester, store);

    await tester.tap(find.byKey(const ValueKey('definir-la-frase')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('campo-de-la-frase')), 'corta');
    await tester.tap(find.byKey(const ValueKey('guardar-la-frase')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('frase-corta')), findsOne);
    expect(await store.read(), isNull, reason: 'no se guardó nada');
  });

  testWidgets('y una que llega al mínimo sí', (tester) async {
    final store = _Memoria();
    final container = await abrir(tester, store);

    await tester.tap(find.byKey(const ValueKey('definir-la-frase')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('campo-de-la-frase')),
      'ocho-o-mas',
    );
    await tester.tap(find.byKey(const ValueKey('guardar-la-frase')));
    await tester.pumpAndSettle();

    expect(await store.read(), const WritePhrase('ocho-o-mas'));
    expect(container.read(writePhraseControllerProvider).value, isTrue);
  });

  testWidgets('el campo va tapado', (tester) async {
    // Se teclea delante de gente, y es un secreto.
    await abrir(tester, _Memoria());
    await tester.tap(find.byKey(const ValueKey('definir-la-frase')));
    await tester.pumpAndSettle();

    final campo = tester.widget<TextField>(
      find.byKey(const ValueKey('campo-de-la-frase')),
    );
    expect(campo.obscureText, isTrue);
  });

  testWidgets('cambiarla cierra el permiso que estuviera abierto', (tester) async {
    // Si no, quien tuviera permiso seguiría escribiendo con una frase que ya no
    // existe — y cambiarla es justo lo que hace alguien que quiere cortar.
    final store = _Memoria(const WritePhrase('la-de-antes'));
    final container = await abrir(tester, store);
    final unlock = container.read(writeUnlockProvider);
    unlock.intentar(guardada: const WritePhrase('la-de-antes'), recibida: 'la-de-antes');
    expect(unlock.puedeEscribir, isTrue);

    await container
        .read(writePhraseControllerProvider.notifier)
        .definir('la-nueva-frase');

    expect(unlock.puedeEscribir, isFalse);
  });

  testWidgets('y quitarla también', (tester) async {
    final store = _Memoria(const WritePhrase('la-de-antes'));
    final container = await abrir(tester, store);
    final unlock = container.read(writeUnlockProvider);
    unlock.intentar(guardada: const WritePhrase('la-de-antes'), recibida: 'la-de-antes');

    await container.read(writePhraseControllerProvider.notifier).borrar();

    expect(unlock.puedeEscribir, isFalse);
    expect(store.borrados, 1);
  });
}

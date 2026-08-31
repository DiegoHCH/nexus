import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/onboarding/domain/repositories/gemini_key_store.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/remote/domain/channel_token.dart';
import 'package:nexus/features/remote/domain/pairing.dart';
import 'package:nexus/features/remote/domain/write_phrase.dart';
import 'package:nexus/features/remote/presentation/providers/channel_token_providers.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus/features/remote/presentation/providers/write_phrase_providers.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/llaves_section.dart';
import 'package:nexus/features/workspace/presentation/providers/las_llaves_guardadas.dart';

/// «Quiero poder ver cuáles tengo guardadas y borrarlas por separado.»
///
/// Hasta ahora la llave de voz no se podía quitar desde ninguna parte: había
/// que abrir Acceso a Llaveros y buscarla por su nombre interno. Y no había
/// dónde ver qué había guardado.
const _valorSecreto = 'AIzaSyEsteValorNoDebeSalirNuncaEnPantalla';

class _Llavero implements GeminiKeyStore {
  _Llavero(this._valor);
  String? _valor;
  var borrada = false;

  @override
  Future<String?> read() async => _valor;
  @override
  Future<void> save(String key) async => _valor = key;
  @override
  Future<void> clear() async {
    borrada = true;
    _valor = null;
  }
}

class _Tokens implements ChannelTokenStore {
  _Tokens(this._token);
  ChannelToken? _token;
  @override
  Future<ChannelToken?> read() async => _token;
  @override
  Future<void> write(ChannelToken token) async => _token = token;
  @override
  Future<void> clear() async => _token = null;
}

class _Frases implements WritePhraseStore {
  _Frases(this._frase);
  WritePhrase? _frase;
  @override
  Future<WritePhrase?> read() async => _frase;
  @override
  Future<void> write(WritePhrase phrase) async => _frase = phrase;
  @override
  Future<void> clear() async => _frase = null;
}

class _Parejas implements PairingStore {
  _Parejas(this._pareja);
  Pairing? _pareja;
  @override
  Future<Pairing?> read() async => _pareja;
  @override
  Future<void> write(Pairing pairing) async => _pareja = pairing;
  @override
  Future<void> clear() async => _pareja = null;
}

void main() {
  late _Llavero llavero;

  ProviderContainer contenedor({
    String? llave = _valorSecreto,
    bool conToken = false,
  }) {
    llavero = _Llavero(llave);
    final c = ProviderContainer(
      overrides: [
        geminiKeyStoreProvider.overrideWithValue(llavero),
        channelTokenStoreProvider.overrideWithValue(
          _Tokens(conToken ? const ChannelToken('t0k3n') : null),
        ),
        writePhraseStoreProvider.overrideWithValue(_Frases(null)),
        pairingStoreProvider.overrideWithValue(_Parejas(null)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('el inventario dice cuáles hay puestas', () async {
    final c = contenedor(conToken: true);

    final hay = await c.read(lasLlavesGuardadasProvider.future);

    expect(hay[LlaveDeNexus.voz], isTrue);
    expect(hay[LlaveDeNexus.tokenDelCanal], isTrue);
    expect(hay[LlaveDeNexus.fraseDeEscritura], isFalse);
    expect(hay[LlaveDeNexus.emparejamiento], isFalse);
  });

  test('la de voz se puede olvidar, que era lo que no se podía', () async {
    final c = contenedor();
    await c.read(lasLlavesGuardadasProvider.future);

    await c.read(olvidarUnaLlaveProvider)(LlaveDeNexus.voz);

    expect(llavero.borrada, isTrue);
    final despues = await c.read(lasLlavesGuardadasProvider.future);
    expect(despues[LlaveDeNexus.voz], isFalse);
  });

  // 🔴 Lo único que la pantalla contesta es «¿está puesta?». El valor no sale
  // ni recortado: iría a cualquier captura y a cualquier pantalla compartida.
  testWidgets('la pantalla no enseña el valor de ninguna llave', (
    tester,
  ) async {
    const strings = NexusStringsEs();
    final c = contenedor();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: NexusTheme.dark(),
          builder: (context, child) =>
              StringsScope(strings: strings, child: child!),
          home: const Scaffold(body: LlavesSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(_valorSecreto), findsNothing);
    expect(find.textContaining('AIzaSy'), findsNothing);
    expect(find.text(strings.keyVoice), findsOne);
    expect(find.text(strings.keyIsSaved), findsOne);
  });

  testWidgets('y solo ofrece olvidar lo que está puesto', (tester) async {
    const strings = NexusStringsEs();
    final c = contenedor();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: NexusTheme.dark(),
          builder: (context, child) =>
              StringsScope(strings: strings, child: child!),
          home: const Scaffold(body: LlavesSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Solo la de voz está puesta: un botón por cada llave enseñaría a no
    // pulsarlos.
    expect(find.text(strings.keyForget), findsOne);
    expect(find.text(strings.keyIsMissing), findsNWidgets(3));
  });
}

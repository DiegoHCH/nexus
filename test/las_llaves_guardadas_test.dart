import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/artifacts/domain/repositories/gemini_image_key_store.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/onboarding/domain/repositories/gemini_key_store.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/remote/domain/channel_token.dart';
import 'package:nexus/features/remote/domain/pairing.dart';
import 'package:nexus/features/remote/domain/write_phrase.dart';
import 'package:nexus/features/remote/presentation/providers/channel_token_providers.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus/features/remote/presentation/providers/write_phrase_providers.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/llaves_section.dart';
import 'package:nexus/features/workspace/presentation/providers/las_llaves_guardadas.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// «Quiero poder ver cuáles tengo guardadas y borrarlas por separado.»
///
/// Y las de imágenes, **una por cuenta de Claude**: el gasto sale de un
/// bolsillo concreto, así que poner la llave solo en `private` es la forma de
/// decir que desde el trabajo no se generan imágenes.
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

/// Guarda una por cuenta, como el de verdad.
class _Imagenes implements GeminiImageKeyStore {
  _Imagenes([Map<String?, String>? puestas]) : _valores = {...?puestas};
  final Map<String?, String> _valores;
  final borradas = <String?>[];

  @override
  Future<String?> read(String? perfil) async => _valores[perfil];
  @override
  Future<void> save(String? perfil, String key) async => _valores[perfil] = key;
  @override
  Future<void> clear(String? perfil) async {
    borradas.add(perfil);
    _valores.remove(perfil);
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
  late _Imagenes imagenes;

  ProviderContainer contenedor({
    String? llave = _valorSecreto,
    Map<String?, String> deImagenes = const {},
    bool conToken = false,
  }) {
    llavero = _Llavero(llave);
    imagenes = _Imagenes(deImagenes);
    final c = ProviderContainer(
      overrides: [
        geminiKeyStoreProvider.overrideWithValue(llavero),
        geminiImageKeyStoreProvider.overrideWithValue(imagenes),
        // Las cuentas se leen del home, y una prueba no puede depender de qué
        // carpetas tenga el Mac donde corre.
        claudeProfilesProvider.overrideWith(
          (ref) async => const [
            ClaudeProfile(
              path: '/Users/alguien/.claude-private',
              name: 'private',
              signedIn: true,
            ),
          ],
        ),
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

  LlaveEnElLlavero deImagenes(List<LlaveEnElLlavero> todas, String? perfil) =>
      todas.firstWhere(
        (l) => l.cual == LlaveDeNexus.imagenes && l.perfil == perfil,
      );

  test('el inventario dice cuáles hay puestas', () async {
    final c = contenedor(conToken: true);

    final hay = await c.read(lasLlavesGuardadasProvider.future);

    expect(hay.firstWhere((l) => l.cual == LlaveDeNexus.voz).hay, isTrue);
    expect(
      hay.firstWhere((l) => l.cual == LlaveDeNexus.tokenDelCanal).hay,
      isTrue,
    );
    expect(
      hay.firstWhere((l) => l.cual == LlaveDeNexus.emparejamiento).hay,
      isFalse,
    );
  });

  // La cuenta de siempre no la lista `claudeProfilesProvider` —para él es la
  // ausencia de perfil— pero se le puede poner llave igual, así que tiene fila.
  test('hay una fila de imágenes por cuenta, incluida la de siempre', () async {
    final c = contenedor();

    final hay = await c.read(lasLlavesGuardadasProvider.future);

    expect(
      hay
          .where((l) => l.cual == LlaveDeNexus.imagenes)
          .map((l) => l.perfil)
          .toList(),
      [null, 'private'],
    );
  });

  test('la de voz se puede olvidar, que era lo que no se podía', () async {
    final c = contenedor();
    final todas = await c.read(lasLlavesGuardadasProvider.future);

    await c.read(olvidarUnaLlaveProvider)(
      todas.firstWhere((l) => l.cual == LlaveDeNexus.voz),
    );

    expect(llavero.borrada, isTrue);
  });

  // 🔴 El caso que motivó todo esto: la llave está solo en una cuenta, y
  // borrarla no puede llevarse la de otra ni la de voz por delante.
  test('cada cuenta tiene la suya, y se borran por separado', () async {
    final c = contenedor(deImagenes: {'private': 'AIzaLaDePrivate'});
    var todas = await c.read(lasLlavesGuardadasProvider.future);

    expect(deImagenes(todas, 'private').hay, isTrue);
    expect(
      deImagenes(todas, null).hay,
      isFalse,
      reason: 'ponerla en private no la pone en la cuenta de siempre',
    );

    await c.read(olvidarUnaLlaveProvider)(deImagenes(todas, 'private'));
    todas = await c.read(lasLlavesGuardadasProvider.future);

    expect(imagenes.borradas, ['private']);
    expect(deImagenes(todas, 'private').hay, isFalse);
    expect(llavero.borrada, isFalse, reason: 'la voz no se toca');
  });

  // 🔴 Lo único que la pantalla contesta es «¿está puesta?». El valor no sale
  // ni recortado: iría a cualquier captura y a cualquier pantalla compartida.
  testWidgets('la pantalla no enseña el valor de ninguna llave', (
    tester,
  ) async {
    const strings = NexusStringsEs();
    final c = contenedor(deImagenes: {'private': 'AIzaLaDePrivate'});

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
    expect(find.textContaining('AIzaLaDePrivate'), findsNothing);
    expect(find.text(strings.keyVoice), findsOne);
    // Y cada fila de imágenes dice de qué cuenta es: sin eso serían dos filas
    // idénticas sin forma de saber cuál se borra.
    expect(find.text(strings.keyImagesFor('private')), findsOne);
    expect(find.text(strings.keyImagesFor(strings.defaultAccount)), findsOne);
  });
}

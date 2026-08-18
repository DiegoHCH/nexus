import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/onboarding/domain/repositories/gemini_key_store.dart';
import 'package:nexus/features/onboarding/domain/repositories/readiness_probe.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/onboarding/presentation/state/onboarding_state.dart';

class _Store implements GeminiKeyStore {
  const _Store(this._value);

  final String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> save(String key) async {}
}

/// El llavero se niega a abrir. Es el escenario de la deuda b5: la llave vive
/// en el llavero del login, y el día que se cambie —o que el sistema deniegue
/// el acceso— esta lectura falla.
class _BrokenStore implements GeminiKeyStore {
  const _BrokenStore();

  @override
  Future<String?> read() async => throw StateError('el llavero no abre');

  @override
  Future<void> save(String key) async {}
}

/// Un sistema con todo en su sitio.
///
/// Se sustituye siempre: sin esto, estas pruebas saldrían a preguntarle al CLI
/// de verdad y su resultado dependería de si **esta** máquina tiene Claude Code
/// instalado y con sesión. Pasarían aquí y fallarían en otro Mac, que es la peor
/// forma de fallar.
class _TodoListo implements ReadinessProbe {
  const _TodoListo();

  @override
  Future<bool> cliInstalled() async => true;

  @override
  Future<bool> anySession() async => true;
}

ProviderContainer containerWith(GeminiKeyStore store) {
  final container = ProviderContainer(
    overrides: [
      geminiKeyStoreProvider.overrideWithValue(store),
      readinessProbeProvider.overrideWithValue(const _TodoListo()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<AppRouteState> resolved(ProviderContainer container) async {
  container.listen(appRouteControllerProvider, (_, _) {});
  expect(container.read(appRouteControllerProvider), isA<AppRouteLoading>());
  // El splash tiene un mínimo de 900 ms a propósito: el orbe se ve aparecer
  // aunque el llavero conteste al instante.
  await Future<void>.delayed(const Duration(milliseconds: 1100));
  return container.read(appRouteControllerProvider);
}

void main() {
  test('con llave guardada se entra directo', () async {
    final state = await resolved(containerWith(const _Store('una-llave')));
    expect(state, isA<AppRouteReady>());
  });

  test('sin llave se pide la configuración', () async {
    final state = await resolved(containerWith(const _Store(null)));
    expect(state, isA<AppRouteNeedsSetup>());
  });

  test('una llave vacía cuenta como no tenerla', () async {
    final state = await resolved(containerWith(const _Store('')));
    expect(state, isA<AppRouteNeedsSetup>());
  });

  // Lo que de verdad estaba en juego: esto corre sin que nadie espere su
  // resultado, así que la excepción no aparecía por ningún lado — el estado se
  // quedaba en «cargando» y la app entera se quedaba en el splash, con el orbe
  // girando y sin decir nada.
  test('si el llavero falla se pide la configuración, no se cuelga', () async {
    final state = await resolved(containerWith(const _BrokenStore()));
    expect(state, isA<AppRouteNeedsSetup>());
  });
}

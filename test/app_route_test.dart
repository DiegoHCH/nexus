import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/onboarding/domain/repositories/gemini_key_store.dart';
import 'package:nexus/features/onboarding/domain/repositories/readiness_probe.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/onboarding/presentation/state/onboarding_state.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/domain/repositories/workspace_store.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// El workspace guardado. Lo que decide a qué pantalla se entra, desde que la
/// llave dejó de decidirlo.
class _Guardado implements WorkspaceStore {
  const _Guardado({this.conCarpeta = true});

  final bool conCarpeta;

  @override
  Future<Workspace> read() async => Workspace(
    folders: conCarpeta
        ? const [PairedFolder(path: '/repo', modality: FolderModality.textOnly)]
        : const [],
  );

  @override
  Future<void> save(Workspace workspace) async {}
}

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

ProviderContainer containerWith(
  GeminiKeyStore store, {
  bool conCarpeta = true,
}) {
  final container = ProviderContainer(
    overrides: [
      geminiKeyStoreProvider.overrideWithValue(store),
      readinessProbeProvider.overrideWithValue(const _TodoListo()),
      workspaceStoreProvider.overrideWithValue(
        _Guardado(conCarpeta: conCarpeta),
      ),
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
  test('con una carpeta emparejada se entra directo', () async {
    final state = await resolved(containerWith(const _Store('una-llave')));
    expect(state, isA<AppRouteReady>());
  });

  // **Lo que cambió, y por qué.** Antes decidía la llave de Gemini, y eso
  // contradecía a la propia app: `Readiness.blocksWork` deja fuera la llave con
  // el motivo escrito —«sin ella se puede trabajar por texto»— y toda carpeta
  // nace en solo texto. Se pedía la credencial de una función apagada para
  // dejarte pasar, y a quien no quisiera dar una llave de Google no le quedaba
  // ninguna forma de usar Nexus.
  test('sin llave se entra igual: la voz es lo único que no habrá', () async {
    final state = await resolved(containerWith(const _Store(null)));
    expect(state, isA<AppRouteReady>());
  });

  test('una llave vacía tampoco cierra la puerta', () async {
    final state = await resolved(containerWith(const _Store('')));
    expect(state, isA<AppRouteReady>());
  });

  // Lo que sí la cierra, y por un motivo que se puede enseñar: sin carpeta,
  // `claude -p` hereda el directorio de la app —`/` para un bundle lanzado por
  // launchd— y el primer encargo responde sobre la raíz del disco.
  test('sin carpeta donde trabajar se pide la configuración', () async {
    final state = await resolved(
      containerWith(const _Store('una-llave'), conCarpeta: false),
    );
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

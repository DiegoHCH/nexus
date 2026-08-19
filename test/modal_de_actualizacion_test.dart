import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/platform/updates_channel.dart';
import 'package:nexus/features/updates/domain/entities/release_check.dart';
import 'package:nexus/features/updates/domain/entities/update_stage.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';
import 'package:nexus/features/updates/presentation/widgets/update_modal.dart';

import 'support/screen_harness.dart';

/// La modal de la actualización, abierta y mirada.
///
/// Es la cara de una decisión: el motor es Sparkle pero su diálogo no se usa, así
/// que **esta pantalla es nuestra y nadie más la comprueba**. Y tiene una fase por
/// cada cosa que puede estar pasando, que es justo la forma de defecto que no se
/// ve hasta que le toca a alguien: la fase que nadie abrió nunca.
///
/// El caso que más importa es el último de aquí: una copia que no puede
/// reemplazarse **no debe ofrecer instalar**. Sin eso, quien abrió Nexus desde
/// Descargas esperaría una descarga entera para chocarse con el muro al final.
class _Fijo extends UpdatesController {
  _Fijo(this._estado);

  final UpdatesState _estado;

  /// Sin llamar a `super.build()`: el de verdad se suscribe al canal nativo, y
  /// aquí lo que se quiere es fijar una fase y mirarla.
  @override
  UpdatesState build() => _estado;
}

void main() {
  const es = NexusStringsEs();
  late Directory support;

  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  Future<void> abrir(
    WidgetTester tester,
    UpdateStage fase, {
    Installability puede = Installability.ok,
    String corriendo = '0.0.2',
  }) => pumpScreen(
    tester,
    const UpdateModal(),
    overrides: [
      updatesControllerProvider.overrideWith(
        () => _Fijo(
          UpdatesState(notice: ReleaseCheck(current: corriendo), stage: fase),
        ),
      ),
      installabilityProvider.overrideWith((ref) async => puede),
    ],
  );

  testWidgets('con versión nueva enseña el salto, el peso y el botón', (
    tester,
  ) async {
    await abrir(
      tester,
      const UpdateFound(version: '0.0.3', bytes: 24000000, notes: 'lo nuevo'),
    );

    expect(find.text(es.updateFoundTitle), findsOne);
    // El salto de una versión a otra, que es la información principal.
    expect(find.text('0.0.2'), findsOne);
    expect(find.text('0.0.3'), findsOne);
    expect(find.text('lo nuevo'), findsOne);
    // El peso se dice antes de empezar: 23 MB en una conexión mala es una
    // decisión, y se toma con el dato delante.
    expect(find.text(es.updateWeight('22.9 MB')), findsOne);
    expect(find.text(es.updateInstall), findsOne);
    expect(find.text(es.updateLater), findsOne);
  });

  testWidgets('si ya venía descargada ofrece reiniciar, no descargar', (
    tester,
  ) async {
    await abrir(
      tester,
      const UpdateFound(
        version: '0.0.3',
        bytes: 24000000,
        alreadyDownloaded: true,
      ),
    );

    expect(find.text(es.updateRestart), findsOne);
    expect(find.text(es.updateInstall), findsNothing);
    // Y sin anunciar un peso que ya no hay que bajar.
    expect(find.text(es.updateWeight('22.9 MB')), findsNothing);
  });

  testWidgets('bajando dice cuánto va de cuánto', (tester) async {
    await abrir(
      tester,
      const UpdateDownloading(received: 12000000, total: 24000000),
    );

    expect(find.text(es.updateDownloading), findsOne);
    expect(find.text(es.updateDownloadedOf('11.4 MB', '22.9 MB')), findsOne);
    // Y se puede cancelar: es una descarga, no un compromiso.
    expect(find.text(es.cancel), findsOne);
  });

  testWidgets('lista para instalarse advierte del reinicio', (tester) async {
    await abrir(tester, const UpdateReady());

    expect(find.text(es.updateReadyTitle), findsOne);
    // El aviso no es relleno: reiniciar puede cortar un `claude -p` a media
    // escritura, y quien lo lee decide con eso delante.
    expect(find.text(es.updateReadyBody), findsOne);
    expect(find.text(es.updateRestart), findsOne);
  });

  testWidgets('instalando ya no se puede cancelar', (tester) async {
    await abrir(tester, const UpdateInstalling());

    expect(find.text(es.updateInstalling), findsOne);
    expect(find.text(es.cancel), findsNothing);
    expect(find.text(es.updateLater), findsNothing);
  });

  testWidgets('un fallo enseña lo que dijo el actualizador', (tester) async {
    await abrir(tester, const UpdateFailed('no se pudo verificar la firma'));

    expect(find.text(es.updateFailedTitle), findsOne);
    expect(find.text('no se pudo verificar la firma'), findsOne);
    expect(find.text(es.updateRetry), findsOne);
  });

  testWidgets('un fallo mudo no deja la modal sin explicación', (tester) async {
    await abrir(tester, const UpdateFailed(''));

    expect(find.text(es.updateFailedBody), findsOne);
  });

  testWidgets('estás al día lo dice con la versión que corre', (tester) async {
    await abrir(tester, const UpdateUpToDate());

    expect(find.text(es.updateUpToDate), findsOne);
    expect(find.text(es.updateUpToDateBody('0.0.2')), findsOne);
  });

  testWidgets('una copia que no puede reemplazarse no ofrece instalar', (
    tester,
  ) async {
    // El caso de la app abierta desde Descargas sin arrastrarla: macOS la corre
    // desde una copia de solo lectura con ruta aleatoria, y desde ahí no hay nada
    // que reemplazar. Medido: la app instalada de esta máquina estaba justo así.
    await abrir(
      tester,
      const UpdateFound(version: '0.0.3', bytes: 24000000),
      puede: Installability.translocated,
    );

    expect(find.text(es.updateMoveTitle), findsOne);
    expect(find.text(es.updateMoveBody), findsOne);
    expect(find.text(es.updateInstall), findsNothing);
    expect(find.text(es.updateRestart), findsNothing);
  });

  testWidgets('y sin poder preguntar tampoco lo ofrece', (tester) async {
    // `unknown` no es «sí». Es la misma regla que en la comprobación de arranque.
    await abrir(
      tester,
      const UpdateFound(version: '0.0.3'),
      puede: Installability.unknown,
    );

    expect(find.text(es.updateMoveTitle), findsOne);
    expect(find.text(es.updateInstall), findsNothing);
  });
}

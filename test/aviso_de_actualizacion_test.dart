import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/updates/presentation/widgets/updates_gate.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/platform/updates_channel.dart';
import 'package:nexus/features/updates/domain/entities/release_check.dart';
import 'package:nexus/features/updates/domain/entities/update_stage.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';
import 'package:nexus/features/updates/presentation/widgets/update_toast.dart';

import 'support/screen_harness.dart';

/// El aviso de actualización, arriba a la derecha, mirado fase por fase.
///
/// Era una modal en el centro y ahora es un toast: una versión nueva es una
/// noticia, no una pregunta que haya que contestar antes de seguir. Lo que no
/// cambia es que **esta superficie es nuestra y nadie más la comprueba**: el
/// motor es Sparkle, pero su diálogo no se usa. Y tiene una fase por
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
    const UpdateToast(),
    overrides: [
      updatesControllerProvider.overrideWith(
        () => _Fijo(
          UpdatesState(
            notice: ReleaseCheck(current: corriendo),
            stage: fase,
          ),
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

  _sobreLasRutas();

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

/// Y que se vea **por encima de una ruta empujada**.
///
/// Es la razón de colgarlo del overlay raíz y no de un `Stack` de la pantalla, y
/// es una afirmación fácil de creer sin comprobar: Ajustes se abre como ruta, y
/// desde ahí también se pulsa «buscar actualizaciones». Colgado más abajo, el
/// aviso saldría **detrás** de Ajustes y parecería que el botón no hace nada.
void _sobreLasRutas() {
  testWidgets('el aviso se ve aunque haya una pantalla abierta encima', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updatesControllerProvider.overrideWith(
            () => _Fijo(
              const UpdatesState(
                notice: ReleaseCheck(current: '0.0.4'),
                stage: UpdateFound(version: '0.0.5'),
              ),
            ),
          ),
          installabilityProvider.overrideWith((ref) async => Installability.ok),
        ],
        child: MaterialApp(
          theme: NexusTheme.dark(),
          builder: (context, child) =>
              StringsScope(strings: const NexusStringsEs(), child: child!),
          home: UpdatesGate(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const Scaffold(body: Text('otra pantalla')),
                      ),
                    ),
                    child: const Text('abrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(const NexusStringsEs().updateFoundTitle), findsOne);

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('otra pantalla'), findsOne, reason: 'la ruta está encima');
    expect(
      find.text(const NexusStringsEs().updateFoundTitle),
      findsOne,
      reason: 'y el aviso sigue a la vista: por eso va en el overlay raíz',
    );
  });
}

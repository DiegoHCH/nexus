import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/platform/updates_channel.dart';
import 'package:nexus/features/updates/domain/entities/release_check.dart';
import 'package:nexus/features/updates/domain/entities/update_stage.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';

// El actualizador: ahora **descarga e instala**, y el motor es Sparkle.
//
// Antes esto solo avisaba con un enlace y sondeaba la API de releases por su
// cuenta. Ese sondeo se fue: dos mecanismos preguntando lo mismo habrían acabado
// discrepando —el aviso diciendo una versión y la modal ofreciendo otra—, así que
// la cadencia la lleva Sparkle y aquí solo se traduce lo que cuenta.
//
// Lo que se vigila: comparar versiones como texto, confundir «no se pudo
// preguntar» con «estás al día», preguntar cada vez que se vuelve a la ventana, y
// ofrecer instalar cuando esta copia no puede reemplazarse.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canal = MethodChannel('com.katanalabs.nexus/updates');

  group('comparar versiones', () {
    test('la publicada más alta se anuncia', () {
      const c = ReleaseCheck(current: '0.0.1', latest: 'v0.0.2');
      expect(c.isNewer, isTrue);
    });

    test('la misma no', () {
      expect(
        const ReleaseCheck(current: '0.0.1', latest: 'v0.0.1').isNewer,
        isFalse,
      );
    });

    test('y una más vieja tampoco', () {
      expect(
        const ReleaseCheck(current: '0.1.0', latest: 'v0.0.9').isNewer,
        isFalse,
      );
    });

    test('la décima versión no se cuenta como menor que la novena', () {
      // Como texto, «0.0.10» < «0.0.9» porque el 1 va antes del 9: el aviso
      // habría desaparecido justo al llegar a la décima. Es el fallo clásico de
      // comparar versiones con `compareTo`.
      expect(ReleaseCheck.compare('0.0.10', '0.0.9'), greaterThan(0));
      expect(
        const ReleaseCheck(current: '0.0.9', latest: 'v0.0.10').isNewer,
        isTrue,
      );
    });

    test('una etiqueta rara no revienta, solo no destaca', () {
      expect(
        const ReleaseCheck(current: '0.0.1', latest: 'v0.0.2-beta.1').isNewer,
        isTrue,
      );
      expect(
        const ReleaseCheck(current: '0.0.1', latest: 'nightly').isNewer,
        isFalse,
      );
    });

    test('no saber no es estar al día', () {
      // `null` en `latest` es «no se pudo preguntar». Decir que estás al día
      // sería afirmar algo que nadie ha comprobado.
      const c = ReleaseCheck(current: '0.0.1');
      expect(c.isNewer, isFalse);
      expect(c.latest, isNull);
    });
  });

  group('ante la duda, no se ofrece instalar', () {
    test('sin poder preguntar no se puede instalar', () {
      // Es la misma regla que en la comprobación de arranque: `unknown` no es
      // «sí». Si esto devolviera `true`, la modal ofrecería una descarga de
      // 23 MB que iba a fallar al final, al no haber nada que reemplazar.
      expect(Installability.unknown.canInstall, isFalse);
      expect(Installability.translocated.canInstall, isFalse);
      expect(Installability.readOnly.canInstall, isFalse);
      expect(Installability.ok.canInstall, isTrue);
    });
  });

  group('cada cuánto se pregunta', () {
    late List<MethodCall> llamadas;

    setUp(() {
      llamadas = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, (call) async {
            llamadas.add(call);
            return call.method == 'installability' ? 'ok' : null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, null);
    });

    ProviderContainer montar(DateTime Function() reloj) {
      final container = ProviderContainer(
        overrides: [
          relojProvider.overrideWithValue(reloj),
          currentVersionProvider.overrideWith((ref) async => '0.0.1'),
        ],
      );
      addTearDown(container.dispose);
      container.listen(updatesControllerProvider, (_, _) {});
      return container;
    }

    int comprobaciones() => llamadas.where((c) => c.method == 'check').length;

    test('al arrancar NO se pregunta desde aquí', () async {
      // Cambió a propósito: antes esto preguntaba al construirse. Ahora el reloj
      // lo lleva Sparkle —`SUScheduledCheckInterval`, dos horas, y una al
      // arrancar—, así que preguntar aquí también sería la segunda comprobación
      // de las dos que se quería evitar.
      montar(() => DateTime(2026, 8, 19, 10));
      await Future<void>.delayed(Duration.zero);

      expect(comprobaciones(), 0);
    });

    test('volver a la ventana pregunta una vez', () async {
      var ahora = DateTime(2026, 8, 19, 10);
      final container = montar(() => ahora);
      await Future<void>.delayed(Duration.zero);

      await container.read(updatesControllerProvider.notifier).alRegresar();
      expect(comprobaciones(), 1);
    });

    test('volver otra vez antes de 15 min no vuelve a preguntar', () async {
      // Sin el tope, cambiar de app y volver diez veces son diez comprobaciones.
      var ahora = DateTime(2026, 8, 19, 10);
      final container = montar(() => ahora);
      await Future<void>.delayed(Duration.zero);
      final control = container.read(updatesControllerProvider.notifier);

      await control.alRegresar();
      ahora = ahora.add(const Duration(minutes: 14));
      await control.alRegresar();

      expect(comprobaciones(), 1, reason: 'aún no toca');
    });

    test('y pasados los 15, sí', () async {
      var ahora = DateTime(2026, 8, 19, 10);
      final container = montar(() => ahora);
      await Future<void>.delayed(Duration.zero);
      final control = container.read(updatesControllerProvider.notifier);

      await control.alRegresar();
      ahora = ahora.add(const Duration(minutes: 16));
      await control.alRegresar();

      expect(comprobaciones(), 2);
    });

    test('la que pide una persona va marcada como manual', () async {
      // La distinción importa: la manual tiene que contestar «estás al día», y la
      // de fondo tiene que callar. Si las dos fueran iguales, o el botón no
      // contestaría o la app sacaría carteles que nadie pidió.
      final container = montar(() => DateTime(2026, 8, 19, 10));
      await Future<void>.delayed(Duration.zero);

      await container.read(updatesControllerProvider.notifier).comprobarAhora();

      final manual = llamadas.lastWhere((c) => c.method == 'check');
      expect((manual.arguments as Map)['manual'], isTrue);
    });
  });

  group('traducir lo que cuenta el actualizador', () {
    UpdatesController montar() {
      final container = ProviderContainer(
        overrides: [
          currentVersionProvider.overrideWith((ref) async => '0.0.1'),
        ],
      );
      addTearDown(container.dispose);
      container.listen(updatesControllerProvider, (_, _) {});
      return container.read(updatesControllerProvider.notifier);
    }

    test('«hay versión nueva» llega a la modal y al aviso', () async {
      final control = montar();
      await Future<void>.delayed(Duration.zero);

      control.aplicar(
        const UpdateEvent(
          name: 'found',
          data: {'version': '0.0.3', 'bytes': 24000000, 'notes': 'lo nuevo'},
        ),
      );

      final estado = control.state;
      expect(estado.stage, isA<UpdateFound>());
      expect((estado.stage as UpdateFound).version, '0.0.3');
      expect((estado.stage as UpdateFound).bytes, 24000000);
      // Y el aviso, que es lo que ve la fila del menú de la barra.
      expect(estado.notice?.isNewer, isTrue);
    });

    test('«estás al día» no se confunde con «no se pudo preguntar»', () async {
      final control = montar();
      await Future<void>.delayed(Duration.zero);

      control.aplicar(const UpdateEvent(name: 'none', data: {}));

      expect(control.state.stage, isA<UpdateUpToDate>());
      // `latest` igual a la que corre, y **no** `null`: null significa que no se
      // pudo preguntar, y aquí sí se preguntó.
      expect(control.state.notice?.latest, '0.0.1');
      expect(control.state.notice?.isNewer, isFalse);
    });

    test('las notas que llegan después no borran la versión', () async {
      // Pueden viajar aparte del feed. Si al pegarlas se reemplazara la fase, la
      // modal se quedaría sin el número de versión a mitad.
      final control = montar();
      await Future<void>.delayed(Duration.zero);

      control.aplicar(
        const UpdateEvent(name: 'found', data: {'version': '0.0.3'}),
      );
      control.aplicar(
        const UpdateEvent(name: 'notes', data: {'notes': 'llegaron luego'}),
      );

      final fase = control.state.stage as UpdateFound;
      expect(fase.version, '0.0.3');
      expect(fase.notes, 'llegaron luego');
    });

    test('sin saber el peso, la barra no finge un porcentaje', () async {
      final control = montar();
      await Future<void>.delayed(Duration.zero);

      control.aplicar(
        const UpdateEvent(name: 'downloading', data: {'received': 1000}),
      );
      expect((control.state.stage as UpdateDownloading).fraction, isNull);

      control.aplicar(
        const UpdateEvent(
          name: 'downloading',
          data: {'received': 50, 'total': 200},
        ),
      );
      expect((control.state.stage as UpdateDownloading).fraction, 0.25);
    });

    test('lo bajado se acumula tal como llega del actualizador', () async {
      // Sparkle manda el trozo, no el total, y el lado nativo es quien suma. Aquí
      // se comprueba que Dart no vuelva a sumar por su cuenta: si lo hiciera, la
      // barra iría al doble de velocidad y se plantaría al llegar al final.
      final control = montar();
      await Future<void>.delayed(Duration.zero);

      control.aplicar(
        const UpdateEvent(
          name: 'downloading',
          data: {'received': 100, 'total': 200},
        ),
      );
      control.aplicar(
        const UpdateEvent(
          name: 'downloading',
          data: {'received': 150, 'total': 200},
        ),
      );

      expect((control.state.stage as UpdateDownloading).received, 150);
    });

    test('un fallo se cuenta con lo que dijo el actualizador', () async {
      final control = montar();
      await Future<void>.delayed(Duration.zero);

      control.aplicar(
        const UpdateEvent(name: 'failed', data: {'message': 'sin red'}),
      );

      expect((control.state.stage as UpdateFailed).message, 'sin red');
    });

    test(
      'al cerrarse vuelve a reposo, que es lo que cierra la modal',
      () async {
        final control = montar();
        await Future<void>.delayed(Duration.zero);

        control.aplicar(
          const UpdateEvent(name: 'found', data: {'version': '0.0.3'}),
        );
        control.aplicar(const UpdateEvent(name: 'closed', data: {}));

        expect(control.state.stage, isA<UpdateIdle>());
      },
    );
  });
}

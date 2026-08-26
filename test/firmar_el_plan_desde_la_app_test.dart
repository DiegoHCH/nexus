import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/workspace/data/datasources/plan_firmado_data_source.dart';
import 'package:nexus/features/workspace/presentation/providers/plan_firmado_providers.dart';
import 'package:nexus/features/workspace/presentation/widgets/firmar_plan_sheet.dart';

/// Firmar el plan desde la app, y que el hook lo acepte.
///
/// **La prueba que cierra el círculo.** Ya estaba probado que el hook deniega sin plan y
/// que los dos lados leen el mismo formato; lo que faltaba es que *la pantalla* produzca
/// una firma que el hook reconozca. Hasta ahora se firmaba escribiendo el JSON a mano, y
/// una firma escrita a mano prueba el formato, no la app.
///
/// Así que aquí se toca el botón y **después se le pregunta al hook de verdad** — el mismo
/// proceso de Python que corre el CLI. Si la UI escribe algo que el hook no entiende, esto
/// se cae; sin este test, se caería en la primera edición de un repo del trabajo y en
/// silencio, que es el peor sitio para enterarse.
///
/// **Todo lo que toca disco o lanza procesos va en `tester.runAsync`.** `testWidgets` corre
/// con un reloj falso, y un `await` de E/S real dentro de él no se cuelga «un rato»: no
/// puede terminar nunca, porque nadie avanza ese reloj. La primera versión de este archivo
/// se quedó parada diez minutos sin imprimir un solo test.
void main() {
  late Directory repo;
  late Directory cuenta;
  const fuente = PlanFirmadoDataSource();
  final hook = File('assets/hooks/exigir_plan.py').absolute.path;

  setUp(() {
    repo = Directory.systemTemp.createTempSync('proyecto');
    cuenta = Directory.systemTemp.createTempSync('cuenta');
  });

  tearDown(() {
    repo.deleteSync(recursive: true);
    cuenta.deleteSync(recursive: true);
  });

  DondeMirar donde() => (carpeta: repo.path, configDir: cuenta.path);

  /// `true` si el hook dejaría escribir en el repo ahora mismo.
  Future<bool> preguntarAlHook() async {
    final proceso = await Process.start(
      'python3',
      [hook],
      workingDirectory: repo.path,
      environment: {'CLAUDE_CONFIG_DIR': cuenta.path},
    );
    proceso.stdin.write(
      jsonEncode({
        'cwd': repo.path,
        'tool_name': 'Edit',
        'tool_input': {'file_path': 'lib/algo.dart'},
      }),
    );
    await proceso.stdin.close();
    final texto = await proceso.stdout.transform(utf8.decoder).join();
    await proceso.exitCode;
    if (texto.trim().isEmpty) return true;
    return jsonDecode(texto)['hookSpecificOutput']['permissionDecision'] !=
        'deny';
  }

  /// Lo mismo desde un `testWidgets`: fuera del reloj falso o no vuelve.
  Future<bool> elHookDejaEscribirEn(WidgetTester tester) async =>
      (await tester.runAsync(preguntarAlHook))!;

  /// La hoja de firmar, montada sola: no hace falta el compositor entero para
  /// comprobar qué escribe al firmar.
  Future<void> abrirLaHoja(WidgetTester tester) async {
    late BuildContext contexto;
    await tester.pumpWidget(
      ProviderScope(
        child: StringsScope(
          strings: const NexusStringsEs(),
          child: MaterialApp(
            theme: NexusTheme.dark(),
            home: Builder(
              builder: (context) {
                contexto = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    // La hoja lee el plan del disco al abrir. Sin salir del reloj falso esa lectura no
    // termina; y `pumpAndSettle` sola vuelve antes de que el archivo esté leído, así que
    // hace falta darle un instante **de reloj real** y pintar después.
    await tester.runAsync(() async {
      FirmarPlanSheet.open(contexto, donde());
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
    });
    await tester.pumpAndSettle();
  }

  /// Pulsa «Firmar» y **espera a que la escritura haya ocurrido**.
  ///
  /// `tester.tap` vuelve cuando el gesto se despacha, no cuando el archivo está en disco:
  /// firmar es asíncrono. Sin esperar, la prueba le preguntaba al hook antes de que la
  /// firma existiera y fallaba **una de cada cinco veces** —medido— con un mensaje que
  /// acusaba a la app de escribir algo que el hook no entiende, que es justo lo contrario
  /// de lo que estaba pasando. Un test que acusa al código correcto es peor que ninguno.
  ///
  /// Se sondea el disco en vez de dormir un rato fijo: dormir es la misma apuesta con
  /// otra cara, y en una máquina cargada vuelve a perder.
  Future<void> pulsarFirmar(WidgetTester tester, {required bool escribe}) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('firmar-el-plan')));
      if (!escribe) {
        // Cuando no debe firmar no hay nada que esperar, pero sí hay que darle margen
        // para firmar mal: seguir al instante haría pasar la prueba sin comprobar nada.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return;
      }
      final limite = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(limite)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // **Vigente y no «hay algo escrito».** Al refirmar ya hay un plan en el disco
        // —el caducado— así que esperar a que exista uno vuelve al instante y deja la
        // carrera igual que estaba.
        final leido = await fuente.leer(cuenta.path, repo.path);
        if (leido != null && leido.vigenteEn(DateTime.now())) break;
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets('firmar en la hoja deja escribir al hook', (tester) async {
    // La carpeta exige plan y no hay ninguno: el punto de partida real.
    await tester.runAsync(
      () => fuente.guardar(
        cuenta.path,
        PlanFirmado(carpeta: repo.path, exige: true),
      ),
    );
    expect(
      await elHookDejaEscribirEn(tester),
      isFalse,
      reason: 'de partida el hook tiene que estar denegando',
    );

    await abrirLaHoja(tester);
    await tester.enterText(
      find.byType(TextField),
      'mover la validación al dominio',
    );
    await pulsarFirmar(tester, escribe: true);

    expect(
      await elHookDejaEscribirEn(tester),
      isTrue,
      reason:
          'se firmó desde la app y el hook sigue denegando: la UI escribe '
          'algo que el hook no entiende',
    );
    // Y lo firmado es lo que se escribió, no un placeholder.
    expect(
      (await tester.runAsync(() => fuente.leer(cuenta.path, repo.path)))!.plan,
      'mover la validación al dominio',
    );
  });

  testWidgets('la hoja no firma nada en blanco', (tester) async {
    await tester.runAsync(
      () => fuente.guardar(
        cuenta.path,
        PlanFirmado(carpeta: repo.path, exige: true),
      ),
    );

    await abrirLaHoja(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await pulsarFirmar(tester, escribe: false);

    // Ni firma ni cierra: si cerrara, quien lo pulsó se iría creyendo que firmó
    // y se encontraría la denegación en la primera edición.
    expect(await elHookDejaEscribirEn(tester), isFalse);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('trae el plan anterior para volver a firmarlo', (tester) async {
    // Refirmar suele ser refirmar lo mismo porque caducó. Obligar a reescribirlo
    // es cómo se acaba firmando «lo de siempre».
    await tester.runAsync(
      () => fuente.guardar(
        cuenta.path,
        PlanFirmado(
          carpeta: repo.path,
          exige: true,
          plan: 'lo de ayer',
          firmado: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
        ),
      ),
    );

    await abrirLaHoja(tester);
    expect(find.text('lo de ayer'), findsOneWidget);

    // Y refirmar sin tocar nada tiene que valer: la fecha la pone la app.
    await pulsarFirmar(tester, escribe: true);
    expect(await elHookDejaEscribirEn(tester), isTrue);
  });

  test('encender la exigencia por carpeta hace que el hook deniegue', () async {
    // El interruptor de Ajustes: sin marca ninguna, encender tiene que crearla.
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);

    expect(
      await preguntarAlHook(),
      isTrue,
      reason: 'una carpeta sin marca no pide nada',
    );

    await contenedor.read(planFirmadoProvider(donde()).future);
    await contenedor.read(planFirmadoProvider(donde()).notifier).exigir(true);

    expect(await preguntarAlHook(), isFalse);
  });

  test('apagar la exigencia no borra el plan que había', () async {
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);
    await contenedor.read(planFirmadoProvider(donde()).future);
    final control = contenedor.read(planFirmadoProvider(donde()).notifier);

    await control.firmar('la frase del plan');
    await control.exigir(false);
    await control.exigir(true);

    // La firma de antes sigue ahí con su fecha: apagar y encender no firma.
    final leido = await fuente.leer(cuenta.path, repo.path);
    expect(leido!.plan, 'la frase del plan');
    expect(leido.firmado, isNotNull);
  });
}

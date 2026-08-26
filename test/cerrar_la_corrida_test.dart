import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/workspace/data/datasources/cierre_de_la_corrida_data_source.dart';
import 'package:nexus/features/workspace/domain/usecases/la_corrida.dart';

/// Cerrar una corrida, y lo que se puede decir de ella cuando termina.
///
/// **Dos cosas se prueban aquí y la segunda es la que importa.** Una es que el cierre se
/// guarde y se apile; la otra es que el resumen **no mienta**: un tramo que no se pudo
/// medir escrito como cero convierte «no lo registramos» en «no costó nada», y ese número
/// acaba en un ticket y luego en una estimación.
void main() {
  late Directory repo;
  late Directory cuenta;
  const fuente = CierreDeLaCorridaDataSource();
  const strings = NexusStringsEs();

  final ayer = DateTime.utc(2026, 8, 25, 9);

  setUp(() {
    repo = Directory.systemTemp.createTempSync('proyecto');
    cuenta = Directory.systemTemp.createTempSync('cuenta');
  });

  tearDown(() {
    repo.deleteSync(recursive: true);
    cuenta.deleteSync(recursive: true);
  });

  Future<List<Cierre>> cerrar(
    String narrativa, {
    String? rama = 'develop',
    ComoTermino como = ComoTermino.cerrada,
  }) => fuente.cerrar(
    cuenta.path,
    repo.path,
    rama: rama,
    como: como,
    narrativa: narrativa,
  );

  group('guardar el cierre', () {
    test('la narrativa es obligatoria: sin ella no se cierra', () async {
      // Un cierre sin narrativa es un booleano con más pasos. Y no lanza: preguntar
      // «¿cerramos?» no puede ejecutar un cierre por el camino.
      expect(await cerrar('   '), isEmpty);
      expect(
        await fuente.leer(cuenta.path, repo.path, rama: 'develop'),
        isEmpty,
      );
    });

    test('se guarda y se vuelve a leer con lo que se escribió', () async {
      await cerrar('el filtro por fecha reusa el bottom sheet del listado');
      final leidos = await fuente.leer(cuenta.path, repo.path, rama: 'develop');
      expect(leidos, hasLength(1));
      expect(leidos.single.narrativa, contains('bottom sheet'));
      expect(leidos.single.como, ComoTermino.cerrada);
    });

    test('cerrar dos veces apila, no sustituye', () async {
      await cerrar('la primera pasada');
      await cerrar('las correcciones del rebote');

      // Guardar solo la última haría desaparecer la primera, que suele ser la más larga.
      final leidos = await fuente.leer(cuenta.path, repo.path, rama: 'develop');
      expect(leidos.map((c) => c.narrativa), [
        'la primera pasada',
        'las correcciones del rebote',
      ]);
    });

    test('cada rama lleva los suyos', () async {
      await cerrar('lo de develop');
      await cerrar('lo del hotfix', rama: 'hotfix/urgente');

      expect(
        (await fuente.leer(
          cuenta.path,
          repo.path,
          rama: 'develop',
        )).single.narrativa,
        'lo de develop',
      );
      expect(
        (await fuente.leer(
          cuenta.path,
          repo.path,
          rama: 'hotfix/urgente',
        )).single.narrativa,
        'lo del hotfix',
      );
    });

    test('las tres salidas se distinguen al leerlas', () async {
      await cerrar('un POC que midió algo', como: ComoTermino.sinProduccion);
      await cerrar('no llevaba a ninguna parte', como: ComoTermino.cancelada);

      final leidos = await fuente.leer(cuenta.path, repo.path, rama: 'develop');
      expect(leidos.map((c) => c.como), [
        ComoTermino.sinProduccion,
        ComoTermino.cancelada,
      ]);
      // Solo una entra en los promedios de trabajo verificado.
      expect(leidos.where((c) => c.como.promedia), isEmpty);
    });
  });

  group('cuándo una corrida está abierta', () {
    test('sin cierres, abierta', () {
      expect(const LaCorrida(rama: 'develop').abierta, isTrue);
    });

    test('con un cierre, cerrada', () {
      final corrida = LaCorrida(
        rama: 'develop',
        cierres: [
          Cierre(
            como: ComoTermino.cerrada,
            narrativa: 'lo de ayer',
            cuando: ayer,
          ),
        ],
      );
      expect(corrida.abierta, isFalse);
      expect(corrida.cierre!.narrativa, 'lo de ayer');
    });

    test('firmar después de cerrar abre una corrida nueva', () {
      // El rebote, sin declarar nada: cuando el PR vuelve con observaciones, lo primero
      // que se hace es decir qué se va a corregir — que es firmar. Pedir además un
      // «empezar de nuevo» sería un trámite para informar de algo que ya se ve.
      final corrida = LaCorrida(
        rama: 'develop',
        plan: 'corregir las observaciones',
        firmado: ayer.add(const Duration(hours: 2)),
        cierres: [
          Cierre(
            como: ComoTermino.cerrada,
            narrativa: 'la primera pasada',
            cuando: ayer,
          ),
        ],
      );

      expect(corrida.abierta, isTrue);
      // Y la anterior no se pierde: sigue ahí, archivada.
      expect(corrida.anteriores, hasLength(1));
      expect(corrida.anteriores.single.narrativa, 'la primera pasada');
    });

    test('firmar antes del cierre no reabre nada', () {
      final corrida = LaCorrida(
        rama: 'develop',
        firmado: ayer.subtract(const Duration(hours: 3)),
        cierres: [
          Cierre(como: ComoTermino.cerrada, narrativa: 'ya está', cuando: ayer),
        ],
      );
      expect(corrida.abierta, isFalse);
      expect(corrida.anteriores, isEmpty);
    });
  });

  group('los tramos', () {
    LaCorrida conFechas({
      DateTime? firmado,
      DateTime? gate,
      DateTime? cerrado,
      bool? verde,
    }) => LaCorrida(
      rama: 'develop',
      plan: 'mover la validación al dominio',
      firmado: firmado,
      gateCorrio: gate,
      gateVerde: verde,
      cierres: [
        if (cerrado != null)
          Cierre(
            como: ComoTermino.cerrada,
            narrativa: 'quedó hecho',
            cuando: cerrado,
          ),
      ],
    );

    test('se miden de firma a gate y de gate a cierre', () {
      final corrida = conFechas(
        firmado: ayer,
        gate: ayer.add(const Duration(hours: 2, minutes: 30)),
        cerrado: ayer.add(const Duration(hours: 3)),
        verde: true,
      );

      expect(corrida.construyendo, const Duration(hours: 2, minutes: 30));
      expect(corrida.cerrando, const Duration(minutes: 30));
      expect(corrida.total, const Duration(hours: 3));
    });

    test('sin gate, el tramo no se inventa', () {
      final corrida = conFechas(
        firmado: ayer,
        cerrado: ayer.add(const Duration(hours: 3)),
      );

      // Cero diría «no costó nada»; nulo dice «no lo sabemos», que es la verdad.
      expect(corrida.construyendo, isNull);
      expect(corrida.cerrando, isNull);
      expect(corrida.total, const Duration(hours: 3));
    });

    test('sin plan firmado, el arranque es la primera señal que haya', () {
      // En una carpeta que no exige plan no hay un acto de arranque, y el gate es lo
      // primero que deja fecha.
      final corrida = conFechas(
        gate: ayer,
        cerrado: ayer.add(const Duration(minutes: 45)),
        verde: true,
      );
      expect(corrida.empezo, ayer);
      expect(corrida.total, const Duration(minutes: 45));
    });

    test('sin nada que fechar, no hay total', () {
      final corrida = LaCorrida(
        rama: 'develop',
        cierres: [
          Cierre(como: ComoTermino.cerrada, narrativa: 'algo', cuando: ayer),
        ],
      );
      expect(corrida.empezo, isNull);
      expect(corrida.total, isNull);
    });

    test('lo que lleva abierta se cuenta mientras dura', () {
      final corrida = conFechas(firmado: ayer);
      expect(
        corrida.llevaEn(ayer.add(const Duration(hours: 1, minutes: 5))),
        const Duration(hours: 1, minutes: 5),
      );
    });

    test('y una vez cerrada ya no se cuenta', () {
      final corrida = conFechas(
        firmado: ayer,
        cerrado: ayer.add(const Duration(hours: 1)),
      );
      expect(corrida.llevaEn(ayer.add(const Duration(hours: 5))), isNull);
    });
  });

  group('el resumen', () {
    test('lo arma el código y sale igual dos veces', () {
      final corrida = LaCorrida(
        rama: 'feat/filtro',
        plan: 'reusar el bottom sheet del listado',
        firmado: ayer,
        gateCorrio: ayer.add(const Duration(hours: 2)),
        gateVerde: true,
        cierres: [
          Cierre(
            como: ComoTermino.cerrada,
            narrativa: 'el filtro por fecha ya está en movimientos',
            cuando: ayer.add(const Duration(hours: 2, minutes: 20)),
          ),
        ],
      );

      final resumen = corrida.resumen(strings);
      expect(resumen, corrida.resumen(strings));
      expect(resumen, contains('feat/filtro'));
      expect(resumen, contains('el filtro por fecha ya está en movimientos'));
      expect(resumen, contains('reusar el bottom sheet'));
      expect(resumen, contains('verde'));
      expect(resumen, contains('2 h 20 min'));
    });

    test('un tramo sin medir se dice, no se escribe como cero', () {
      final corrida = LaCorrida(
        rama: 'develop',
        cierres: [
          Cierre(
            como: ComoTermino.cerrada,
            narrativa: 'algo salió',
            cuando: ayer,
          ),
        ],
      );

      final resumen = corrida.resumen(strings);
      expect(resumen, contains('no se puede saber'));
      expect(resumen, isNot(contains('0 min')));
      // Y que el gate no corriera no se lee como que fue mal.
      expect(resumen, contains('no llegó a correr'));
    });

    test('el gate en rojo y el gate sin correr no dicen lo mismo', () {
      String conGate(bool? verde) => LaCorrida(
        rama: 'develop',
        gateVerde: verde,
        cierres: [
          Cierre(como: ComoTermino.cerrada, narrativa: 'x', cuando: ayer),
        ],
      ).resumen(strings);

      expect(conGate(false), contains('rojo'));
      expect(conGate(null), contains('no llegó a correr'));
      expect(conGate(false), isNot(conGate(null)));
    });

    test('una corrida abierta lo dice en vez de fingir un cierre', () {
      final resumen = const LaCorrida(rama: 'develop').resumen(strings);
      expect(resumen, contains('Todavía abierta'));
    });

    test('sin producción y cancelada quedan escritas como tales', () {
      String conSalida(ComoTermino como) => LaCorrida(
        rama: 'develop',
        firmado: ayer,
        cierres: [
          Cierre(
            como: como,
            narrativa: 'lo que fuera',
            cuando: ayer.add(const Duration(hours: 1)),
          ),
        ],
      ).resumen(strings);

      expect(
        conSalida(ComoTermino.sinProduccion),
        contains('No va a producción'),
      );
      expect(conSalida(ComoTermino.cancelada), contains('no dejó nada'));
      // Y las dos siguen midiendo el tiempo: cancelar algo que avanzó pierde el dato, y
      // ese es justo el error que «sin producción» existe para evitar.
      expect(conSalida(ComoTermino.sinProduccion), contains('Llevó 1 h.'));
    });
  });
}

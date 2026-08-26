import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/data/datasources/cierre_de_la_corrida_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/gate_del_repo_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/plan_firmado_data_source.dart';
import 'package:nexus/features/workspace/presentation/providers/corrida_providers.dart';

/// La lista de todas las corridas de una cuenta, y la limpieza de las huérfanas.
///
/// **Lo que se prueba es que la lista no esconda nada y no borre de más.** Las dos formas
/// de que esto no sirva son simétricas: que una corrida abierta no aparezca —y entonces
/// la lista es un archivo histórico en vez de una mesa de trabajo— o que la limpieza se
/// lleve por delante una rama viva, que es perder trabajo sin poder deshacerlo.
void main() {
  late Directory cuenta;
  late Directory repo;
  const planes = PlanFirmadoDataSource();
  const gates = GateDelRepoDataSource();
  const cierres = CierreDeLaCorridaDataSource();

  Future<String> enElRepo(List<String> args) async {
    final hecho = await Process.run(
      'git',
      ['-C', repo.path, ...args],
      environment: {'GIT_CONFIG_GLOBAL': '/dev/null'},
    );
    expect(hecho.exitCode, 0, reason: '${args.join(' ')}: ${hecho.stderr}');
    return (hecho.stdout as String).trim();
  }

  setUp(() async {
    cuenta = Directory.systemTemp.createTempSync('cuenta');
    repo = Directory.systemTemp.createTempSync('proyecto');
    await enElRepo(['init', '-b', 'develop']);
    await enElRepo(['config', 'user.email', 'nadie@ejemplo.test']);
    await enElRepo(['config', 'user.name', 'Nadie']);
    File('${repo.path}/algo.txt').writeAsStringSync('uno\n');
    await enElRepo(['add', '.']);
    await enElRepo(['commit', '-m', 'primero']);
  });

  tearDown(() {
    cuenta.deleteSync(recursive: true);
    if (repo.existsSync()) repo.deleteSync(recursive: true);
  });

  Future<void> firmar(String rama, String plan) => planes.guardar(
    cuenta.path,
    PlanFirmado(
      carpeta: repo.path,
      rama: rama,
      exige: true,
      plan: plan,
      firmado: DateTime.now().toUtc(),
    ),
  );

  Future<void> gateVerde(String rama) => gates.guardar(
    cuenta.path,
    GateDelRepo(
      carpeta: repo.path,
      rama: rama,
      resultado: ResultadoDelGate.verde,
      cuando: DateTime.now().toUtc(),
      huella: 'lo-que-sea',
    ),
  );

  Future<List<CorridaEnLaLista>> laLista() async {
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);
    return contenedor.read(todasLasCorridasProvider(cuenta.path).future);
  }

  group('qué entra en la lista', () {
    test('vacía cuando no hay nada anotado', () async {
      expect(await laLista(), isEmpty);
    });

    test('una corrida abierta aparece, aunque no tenga cierre', () async {
      // Es la razón de juntar las tres marcas en vez de listar los cierres: empezar por
      // los cierres daría una lista de cosas terminadas, y lo que uno busca al abrirla es
      // lo que tiene entre manos.
      await firmar('feat/algo', 'mover la validación al dominio');

      final lista = await laLista();
      expect(lista, hasLength(1));
      expect(lista.single.corrida.rama, 'feat/algo');
      expect(lista.single.corrida.abierta, isTrue);
      expect(lista.single.corrida.plan, 'mover la validación al dominio');
    });

    test('una corrida que solo tiene gate también', () async {
      // Una carpeta que no exige plan no deja firma, y su trabajo no puede desaparecer
      // de la lista por eso.
      await gateVerde('develop');
      final lista = await laLista();
      expect(lista.single.corrida.rama, 'develop');
      expect(lista.single.corrida.gateVerde, isTrue);
    });

    test('las tres marcas de una rama se juntan en una sola fila', () async {
      await firmar('develop', 'lo acordado');
      await gateVerde('develop');
      await cierres.cerrar(
        cuenta.path,
        repo.path,
        rama: 'develop',
        como: ComoTermino.cerrada,
        narrativa: 'quedó hecho',
      );

      final lista = await laLista();
      expect(lista, hasLength(1));
      expect(lista.single.corrida.plan, 'lo acordado');
      expect(lista.single.corrida.gateVerde, isTrue);
      expect(lista.single.corrida.cierre!.narrativa, 'quedó hecho');
    });

    test('cada rama es una fila', () async {
      await firmar('develop', 'lo de develop');
      await firmar('feat/otra', 'lo de la otra');
      // Sin orden: las dos se firman en el mismo instante y ordenarlas entre sí sería
      // pedirle a la prueba que fije algo que no está decidido.
      expect(
        (await laLista()).map((f) => f.corrida.rama),
        containsAll(<String>['develop', 'feat/otra']),
      );
    });
  });

  group('el orden', () {
    test('las abiertas van antes que las cerradas', () async {
      await cierres.cerrar(
        cuenta.path,
        repo.path,
        rama: 'develop',
        como: ComoTermino.cerrada,
        narrativa: 'cerrada hace nada',
      );
      await firmar('feat/viva', 'esto sigue');

      // Ordenar solo por fecha entierra lo que está vivo debajo de lo que se cerró ayer.
      final lista = await laLista();
      expect(lista.first.corrida.rama, 'feat/viva');
      expect(lista.last.corrida.rama, 'develop');
    });
  });

  group('las huérfanas', () {
    test('una rama que existe no es huérfana', () async {
      await firmar('develop', 'lo de siempre');
      expect((await laLista()).single.huerfana, isFalse);
    });

    test('una rama borrada sí', () async {
      await enElRepo(['switch', '-c', 'feat/efimera']);
      await firmar('feat/efimera', 'algo rápido');
      await enElRepo(['switch', 'develop']);
      await enElRepo(['branch', '-D', 'feat/efimera']);

      final lista = await laLista();
      expect(lista.single.huerfana, isTrue);
    });

    test('y una carpeta que ya no está, también', () async {
      await firmar('develop', 'lo de un repo que se fue');
      repo.deleteSync(recursive: true);
      expect((await laLista()).single.huerfana, isTrue);
    });
  });

  group('limpiar', () {
    Future<void> limpiar(String? rama) async {
      final contenedor = ProviderContainer();
      addTearDown(contenedor.dispose);
      await contenedor
          .read(limpiarCorridasProvider.notifier)
          .borrar(cuenta.path, repo.path, rama);
    }

    test('se lleva las tres marcas de esa rama', () async {
      await firmar('feat/vieja', 'algo');
      await gateVerde('feat/vieja');
      await cierres.cerrar(
        cuenta.path,
        repo.path,
        rama: 'feat/vieja',
        como: ComoTermino.cerrada,
        narrativa: 'terminado',
      );

      await limpiar('feat/vieja');

      expect(
        (await planes.leer(cuenta.path, repo.path, rama: 'feat/vieja'))?.plan,
        isNull,
      );
      expect(
        (await gates.leer(
          cuenta.path,
          repo.path,
          rama: 'feat/vieja',
        )).resultado,
        ResultadoDelGate.sinCorrer,
      );
      expect(
        await cierres.leer(cuenta.path, repo.path, rama: 'feat/vieja'),
        isEmpty,
      );
    });

    test('y no toca las demás ramas', () async {
      await firmar('feat/vieja', 'la que se va');
      await firmar('develop', 'la que se queda');

      await limpiar('feat/vieja');

      expect(
        (await planes.leer(cuenta.path, repo.path, rama: 'develop'))?.plan,
        'la que se queda',
      );
      expect((await laLista()).map((f) => f.corrida.rama), ['develop']);
    });

    test('lo que es de la carpeta y no de una rama se queda', () async {
      // `exige` es de la carpeta: borrarlo al limpiar una rama apagaría un interruptor
      // que nadie tocó, y el gate dejaría de pedir plan sin que nada lo dijera.
      await firmar('feat/vieja', 'algo');
      await limpiar('feat/vieja');

      final marca = await planes.leer(cuenta.path, repo.path, rama: 'develop');
      expect(marca, isNotNull);
      expect(marca!.exige, isTrue);
    });
  });
}

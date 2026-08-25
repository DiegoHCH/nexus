import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/superpowers/data/datasources/skills_data_source.dart';
import 'package:nexus/features/superpowers/domain/usecases/fallos_por_cuenta.dart';

/// Instalar en todas las cuentas de una vez.
///
/// Existe por un desajuste que ya estaba en la maquina: `canvas-design` y
/// `frontend-design` puestas en dos cuentas y `skill-creator` en una sola, porque
/// instalarlas era ir cambiando de pestaña a mano. Lo instalado en una cuenta es
/// **invisible** para las carpetas de la otra —tambien para sus encargos, que corren con
/// la cuenta de su carpeta— y el sintoma no menciona cuentas en ninguna parte: «en esta
/// carpeta funciona y en esta no».
void main() {
  group('lo que se cuenta cuando falla', () {
    test('sin fallos, no hay nada que decir', () {
      expect(FallosPorCuenta.primero(const {}), isNull);
    });

    test('un solo fallo se cuenta tal cual', () {
      // El CLI dice cosas accionables —«ya existe uno con ese nombre»— y adornarlas
      // solo estorba.
      expect(
        FallosPorCuenta.primero(const {
          '/work': 'ya existe uno con ese nombre',
        }),
        'ya existe uno con ese nombre',
      );
    });

    test('varios fallos dicen cuantas cuentas, y eso importa', () {
      // **Instalar en dos y fallar en la tercera es un resultado distinto** de no
      // instalar en ninguna, y las dos cosas caben en un «no se pudo». Sin el numero,
      // «ya existe uno con ese nombre» hace pensar que el problema es de la cuenta que
      // se esta mirando.
      final texto = FallosPorCuenta.primero(const {
        '/work': 'ya existe uno con ese nombre',
        '/private': 'ya existe uno con ese nombre',
      });

      expect(texto, contains('ya existe uno con ese nombre'));
      expect(texto, contains('2'));
    });
  });

  group('lo que hace el reparto', () {
    test('sigue con las demas cuentas aunque una falle', () async {
      // **El fallo de una cuenta no puede dejar sin instalar las que si se podian.**
      // Cortar en el primer error seria peor que no repartir: quedaria instalado en
      // una, sin instalar en otra, y sin decir en cuales.
      final fuente = _Instalador({'/roto': 'no se pudo escribir'});

      final fallos = await fuente.installEn(
        ['/work', '/roto', '/private'],
        repoRaw: 'quien/sea',
        id: 'mobile-design',
      );

      // Se intentaron las tres, en orden, y no se paro en la del medio.
      expect(fuente.intentadas, ['/work', '/roto', '/private']);
      // Y el error va **con su cuenta**: un «no se pudo» suelto no dice donde quedo.
      expect(fallos, {'/roto': 'no se pudo escribir'});
    });

    test('sin fallos, el mapa viene vacio', () async {
      final fuente = _Instalador(const {});
      expect(
        await fuente.installEn(['/work', '/private'], repoRaw: 'q/s', id: 'x'),
        isEmpty,
      );
    });

    test('el repo se trae una vez, no una por cuenta', () async {
      // El clon es lo que cuesta; repetirlo por cuenta seria pagar la red tres veces
      // por lo mismo. Se comprueba en la fuente porque el clon lo hace un metodo
      // privado y lo que importa es que el bucle este **dentro** de `installEn` y no
      // envolviendola.
      final codigo = File(
        'lib/features/superpowers/data/datasources/skills_data_source.dart',
      ).readAsStringSync();
      final desde = codigo.indexOf('Future<Map<String, String>> installEn');
      final cuerpo = codigo.substring(desde, codigo.indexOf('\n  }\n', desde));

      expect(cuerpo, contains('for (final configDir in configDirs)'));
      expect(
        cuerpo,
        isNot(contains('_fetch')),
        reason:
            'installEn clona por su cuenta: el clon se repetiria por cuenta',
      );
    });
  });

  test('la casilla nace apagada y no se recuerda', () {
    // Instalar en cuentas que no se estan mirando es un efecto que hay que **pedir**,
    // no heredar. Y no se guarda entre visitas por lo mismo: una casilla marcada la
    // semana pasada tocaria cuentas sin que nadie lo decida hoy.
    final fuente = File(
      'lib/features/superpowers/presentation/widgets/superpowers_section.dart',
    ).readAsStringSync();

    expect(fuente, contains('var _enTodas = false;'));
    expect(
      fuente,
      isNot(contains('SharedPreferences')),
      reason: 'la casilla se empezo a recordar entre visitas',
    );
  });

  test('el aviso desaparece cuando deja de ser verdad', () {
    // Con la casilla marcada, «solo lo veran las carpetas de esta cuenta» es falso, y
    // un aviso que miente es peor que ninguno.
    final fuente = File(
      'lib/features/superpowers/presentation/widgets/superpowers_section.dart',
    ).readAsStringSync();

    expect(fuente, contains('if (!enTodas)'));
    expect(fuente, contains('superpowersOnlyHere'));
  });
}

/// Un instalador que no toca el disco ni la red.
///
/// Hace falta porque el de verdad construye la URL de GitHub a partir del nombre del
/// repo, asi que no hay forma de apuntarlo a un clon local — y lo que hay que ejercitar
/// aqui no es el clon, es **el reparto**: que siga con las demas cuentas cuando una
/// falla y que diga en cuales fallo.
class _Instalador extends SkillsDataSource {
  _Instalador(this.fallos);

  /// Qué cuenta falla y con qué mensaje.
  final Map<String, String> fallos;

  /// En qué orden se intentaron, para poder afirmar que no se corto a la mitad.
  final intentadas = <String>[];

  @override
  Future<String?> install(
    String configDir, {
    required String repoRaw,
    required String id,
  }) async {
    intentadas.add(configDir);
    return fallos[configDir];
  }
}

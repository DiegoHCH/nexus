import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/platform/herramienta_externa.dart';
import 'package:nexus/features/assistant/data/datasources/gemini_live_data_source.dart';
import 'package:nexus/features/e2e/domain/usecases/donde_vive_el_repo_de_pruebas.dart';
import 'package:nexus/features/e2e/presentation/providers/repo_de_pruebas_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SEC-05, 06 y 07: los tres son endurecimiento y ninguno cambia lo que se ve.
/// Van juntos porque comparten forma — un valor que entra por un camino y se usa
/// por otro, sin que nadie compruebe nada en medio.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // SEC-05. El `PATH` que monta la app antepone `/opt/homebrew/bin` y
  // `/usr/local/bin`, que en un Mac con Homebrew los escribe el usuario sin
  // pedir contraseña. Anteponerlos es correcto —una app de GUI no hereda el
  // `PATH` de la shell—; lo que faltaba es decidirlo una vez en vez de dejar que
  // el sistema lo resuelva en cada arranque.
  // Lo que costó una instalación fallida el primer día que la usó alguien que no
  // era yo: `claude` estaba instalado, funcionaba en su terminal, y Nexus decía
  // que no. Estaba dentro de una versión de Node gestionada por fnm.
  group('donde fnm y nvm esconden lo que instala npm', () {
    late Directory casa;

    setUp(() {
      casa = Directory.systemTemp.createTempSync('casa_de_prueba');
    });
    tearDown(() => casa.deleteSync(recursive: true));

    void inventa(String ruta) =>
        File('${casa.path}/$ruta').createSync(recursive: true);

    test('encuentra el binario dentro de una versión de fnm', () {
      inventa('.local/share/fnm/node-versions/v22.3.0/installation/bin/claude');

      expect(
        HerramientaExterna.enLosGestoresDeNode(casa.path, 'claude'),
        contains(
          '${casa.path}/.local/share/fnm/node-versions/v22.3.0'
          '/installation/bin/claude',
        ),
      );
    });

    // nvm no mete el nivel `installation/`, así que se prueban las dos formas.
    test('y dentro de una de nvm, que tiene otra forma', () {
      inventa('.nvm/versions/node/v20.11.0/bin/claude');

      expect(
        HerramientaExterna.enLosGestoresDeNode(casa.path, 'claude'),
        contains('${casa.path}/.nvm/versions/node/v20.11.0/bin/claude'),
      );
    });

    // Con varias instaladas gana la más nueva: es la que el usuario tiene activa
    // casi siempre, y probar primero la vieja daría una versión de Claude que no
    // es la que usa en su terminal.
    test('con varias versiones, la más nueva va primero', () {
      for (final v in ['v18.19.0', 'v20.11.0', 'v22.3.0']) {
        inventa('.nvm/versions/node/$v/bin/claude');
      }

      final donde = HerramientaExterna.enLosGestoresDeNode(casa.path, 'claude');
      final soloNvm = [
        for (final r in donde)
          if (r.contains('.nvm')) r,
      ];

      expect(soloNvm.first, contains('v22.3.0'));
      expect(soloNvm.last, contains('v18.19.0'));
    });

    test('sin ningún gestor instalado no inventa rutas', () {
      expect(
        HerramientaExterna.enLosGestoresDeNode(casa.path, 'claude'),
        isEmpty,
      );
    });

    test('y sin HOME tampoco', () {
      expect(HerramientaExterna.enLosGestoresDeNode('', 'claude'), isEmpty);
    });
  });

  // 🔴 Estos dos no prueban comportamiento: fijan decisiones que se deshacen
  // solas al «simplificar», y cuyo fallo **solo se ve en la máquina de otro**.
  group('cómo se le pregunta al shell del usuario', () {
    // `-lc` no lee `.zshrc` y `-lic` sí, medido con un ZDOTDIR de prueba, y ahí
    // es donde se configuran fnm, nvm y volta.
    test('en modo interactivo, o no ve el gestor de Node', () {
      expect(HerramientaExterna.banderasDelShell, contains('-i'));
      expect(HerramientaExterna.banderasDelShell, contains('-l'));
    });

    // Combinar cortas en `-lic` es costumbre de bash y zsh, no una garantía.
    test('y con las banderas sueltas, que aquí no todos usan zsh', () {
      expect(HerramientaExterna.banderasDelShell, hasLength(3));
      expect(HerramientaExterna.banderasDelShell.last, '-c');
    });
  });

  group('el PATH que declara el shell', () {
    test('de zsh y bash viene con dos puntos', () {
      expect(
        HerramientaExterna.carpetasDelPath('/usr/bin:/opt/homebrew/bin\n'),
        '/usr/bin:/opt/homebrew/bin',
      );
    });

    // 🔴 fish lo imprime **separado por espacios**: para él el PATH es una lista
    // y no una cadena. Sin esto, su PATH entero se leía como una sola carpeta
    // con espacios dentro y no se encontraba nada — que es exactamente lo que le
    // pasaba a quien usa fish.
    test('y el de fish viene con espacios', () {
      expect(
        HerramientaExterna.carpetasDelPath('/usr/bin /opt/homebrew/bin\n'),
        '/usr/bin:/opt/homebrew/bin',
      );
    });

    test('mezclados también, y sin dejar huecos', () {
      expect(
        HerramientaExterna.carpetasDelPath('  /a:/b  /c \n /d  '),
        '/a:/b:/c:/d',
      );
    });

    test('una salida vacía no da carpetas', () {
      expect(HerramientaExterna.carpetasDelPath('   \n '), '');
    });
  });

  group('la ruta de una herramienta', () {
    setUp(HerramientaExterna.olvidar);

    test('se resuelve a ruta absoluta, no al nombre', () async {
      final donde = await HerramientaExterna.ruta(
        'git',
        candidatos: const ['/opt/homebrew/bin/git', '/usr/bin/git'],
        existe: (ruta) => ruta == '/usr/bin/git',
        preguntaAlShell: (_) async => null,
        path: '',
      );

      expect(donde, '/usr/bin/git');
    });

    test('y se resuelve una sola vez', () async {
      await HerramientaExterna.ruta(
        'git',
        candidatos: const ['/opt/homebrew/bin/git'],
        existe: (_) => true,
        preguntaAlShell: (_) async => null,
        path: '',
      );

      // La segunda vez no encontraría nada, y aun así contesta lo de antes: la
      // decisión ya está tomada. Es lo que evita que un binario que aparezca a
      // media sesión en un directorio que el usuario escribe se cuele en el
      // siguiente encargo.
      final otra = await HerramientaExterna.ruta(
        'git',
        candidatos: const ['/opt/homebrew/bin/git'],
        existe: (_) => false,
        preguntaAlShell: (_) async => null,
        path: '',
      );

      expect(otra, '/opt/homebrew/bin/git');
    });

    test('si no está en ningún sitio, falla como fallaba antes', () async {
      final donde = await HerramientaExterna.ruta(
        'noexiste',
        candidatos: const ['/opt/homebrew/bin/noexiste'],
        existe: (_) => false,
        preguntaAlShell: (_) async => null,
        path: '',
      );

      // El nombre a secas: entonces `Process.start` lanza su `ProcessException`
      // de siempre, en vez de estrenar una forma nueva de romperse.
      expect(donde, 'noexiste');
    });

    // Lo de arriba puede estar perfecto y quedar un sitio lanzando por nombre.
    // Es una invariante de todo el repo, así que se comprueba sobre todo el repo.
    test('y nadie lanza claude ni git por su nombre', () {
      final culpables = <String>[];
      for (final archivo
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              // El propio resolutor los nombra: es su trabajo.
              .where((f) => !f.path.endsWith('herramienta_externa.dart'))) {
        final texto = archivo
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        for (final patron in [
          RegExp(r"Process\.(run|start)\(\s*'(claude|git)'"),
          RegExp(r"Process\.(run|start)\(\s*\n\s*'(claude|git)'"),
        ]) {
          if (patron.hasMatch(texto)) {
            culpables.add(archivo.path.split('/').last);
          }
        }
      }

      expect(culpables, isEmpty);
    });
  });

  // SEC-06. `elegir()` comprobaba la forma del slug; `_cargar()` tomaba lo que
  // hubiera en las preferencias sin volver a mirarlo — y las preferencias son un
  // plist en el disco, no un almacén de confianza. A tres líneas de donde se usa
  // hay un `delete(recursive: true)`.
  group('el slug del repo de pruebas', () {
    test('lo que tiene forma de slug pasa, con espacios de más incluidos', () {
      expect(
        DondeViveElRepoDePruebas.valido('  global66/automated-test  '),
        'global66/automated-test',
      );
    });

    test('lo que no la tiene, no', () {
      for (final malo in [
        '../../etc/passwd',
        'sin-barra',
        'con/dos/barras',
        'con espacio/nombre',
        '',
      ]) {
        expect(DondeViveElRepoDePruebas.valido(malo), isNull, reason: malo);
      }
    });

    test('un slug corrupto en las preferencias no se adopta', () async {
      SharedPreferences.setMockInitialValues({
        'pruebas.repo.slug': '../../../algo',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);

      c.read(slugDelRepoDePruebasProvider);
      await c.read(slugDelRepoDePruebasProvider.notifier).cargada;

      expect(
        c.read(slugDelRepoDePruebasProvider),
        DondeViveElRepoDePruebas.slugPorDefecto,
        reason: 'lo que no pasa la forma se queda en el de por defecto',
      );
    });

    test('y uno bueno sí', () async {
      SharedPreferences.setMockInitialValues({
        'pruebas.repo.slug': 'otro/repo',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);

      c.read(slugDelRepoDePruebasProvider);
      await c.read(slugDelRepoDePruebasProvider.notifier).cargada;

      expect(c.read(slugDelRepoDePruebasProvider), 'otro/repo');
    });
  });

  // SEC-07. Que la llave viaje en la query es lo que documenta Google; lo que
  // faltaba es escaparla.
  group('la dirección de Gemini', () {
    test('la llave va escapada', () {
      final url = GeminiLiveDataSource.urlPara('AIza+con/signos=raros');

      expect(url.queryParameters['key'], 'AIza+con/signos=raros');
      // Escapada en el texto: es lo que de verdad viaja.
      expect(url.toString(), contains('AIza%2Bcon%2Fsignos%3Draros'));
    });

    // Lo que pasaba de verdad: una llave pegada con un salto de línea daba una
    // URL rota y un error de conexión que no se parece a «revisa la llave».
    test('una llave con espacios de más no rompe la dirección', () {
      final url = GeminiLiveDataSource.urlPara(' AIzaSyLoQueSea\n');

      expect(url.queryParameters['key'], 'AIzaSyLoQueSea');
      expect(url.scheme, 'wss');
      expect(url.host, 'generativelanguage.googleapis.com');
    });
  });
}

import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';

/// **La cuenta de siempre también es una cuenta.**
///
/// 🔴 **Reportado con captura, y por otra persona:** en su Mac el chat
/// funcionaba perfectamente y Ajustes → Superpoderes decía «No hay ninguna
/// cuenta de Claude configurada», sin dejar ver ni poner nada. Y era cierto
/// desde su punto de vista: no tenía perfiles con nombre —lo normal si nadie ha
/// creado ninguno— y `ClaudeProfilesDataSource.list()` devuelve solo las
/// `.claude-*`.
///
/// Esa omisión está bien donde nació —al **elegir** la cuenta de una carpeta, «la
/// de siempre» es la ausencia de perfil y ya está arriba como opción, así que
/// listarla la enseñaría dos veces— y está mal donde se **mira qué tiene
/// instalado** una cuenta: la de siempre tiene sus servidores MCP, sus skills y
/// sus plugins como cualquier otra.
void main() {
  group('dónde se busca su credencial', () {
    // 🔴 **La de siempre puede guardarla sin sufijo.** Su entrada se llama
    // «Claude Code-credentials» a secas —lo dice el comentario del propio
    // código y se comprobó en el llavero de este Mac—, así que buscándola solo
    // por el hash de su ruta salía **sin sesión** aunque la tuviera. Y eso se
    // lee como «esta cuenta no sirve».
    test('la de siempre, en los dos sitios', () {
      final sitios = ClaudeProfilesDataSource.keychainServices(
        '/Users/alguien/.claude',
      );

      expect(sitios, contains('Claude Code-credentials'));
      expect(
        sitios,
        contains(
          ClaudeProfilesDataSource.keychainService('/Users/alguien/.claude'),
        ),
        reason: 'en esta máquina existen las dos entradas a la vez',
      );
    });

    test('y una con nombre, solo en el de su ruta', () {
      expect(
        ClaudeProfilesDataSource.keychainServices(
          '/Users/alguien/.claude-work',
        ),
        [
          ClaudeProfilesDataSource.keychainService(
            '/Users/alguien/.claude-work',
          ),
        ],
      );
    });

    // Dos cuentas distintas no pueden compartir servicio: sería leer las
    // credenciales de una creyendo que son de la otra.
    test('dos cuentas con nombre no comparten servicio', () {
      expect(
        ClaudeProfilesDataSource.keychainService('/Users/alguien/.claude-work'),
        isNot(
          ClaudeProfilesDataSource.keychainService(
            '/Users/alguien/.claude-private',
          ),
        ),
      );
    });
  });

  // 🔴 **Preguntado antes de ponerle nombre a nada:** «¿se puede saber con qué
  // correo está logueada la cuenta?». Sí, y estaba a la vista: Claude Code lo
  // guarda en el `.claude.json` de cada directorio, en `oauthAccount`. Con eso
  // una cuenta no necesita un nombre inventado — ya tiene el suyo.
  //
  // Y contesta una pregunta que no se sabía hacer: en el Mac donde se midió,
  // `.claude` y `.claude-work` resultaron ser **la misma cuenta** —mismo correo
  // y misma organización— y solo `.claude-private` era otra. Sin el correo,
  // tres perfiles parecen tres cuentas.
  group('con qué correo está iniciada', () {
    late Directory casa;

    setUp(() => casa = Directory.systemTemp.createTempSync('cuentas'));
    tearDown(() => casa.deleteSync(recursive: true));

    File elArchivo() => File('${casa.path}/.claude.json');

    test('sale del .claude.json de esa cuenta', () async {
      elArchivo().writeAsStringSync(
        jsonEncode({
          'oauthAccount': {
            'emailAddress': 'alguien@empresa.com',
            'displayName': 'Alguien',
            'organizationName': 'Empresa - Equipo',
          },
          'mcpServers': <String, Object?>{},
        }),
      );

      final quienEs = await const ClaudeProfilesDataSource().datosDe(casa.path);

      expect(quienEs.correo, 'alguien@empresa.com');
      // La organización sale del mismo sitio, y de ella el nombre que se
      // enseña. Ver [ElNombreDeLaCuenta].
      expect(quienEs.organizacion, 'Empresa - Equipo');
    });

    test(
      'sin archivo, sin sesión o a medias, no se sabe y no revienta',
      () async {
        const fuente = ClaudeProfilesDataSource();

        // Sin archivo: la cuenta existe pero nunca se entró.
        expect((await fuente.datosDe(casa.path)).correo, isNull);

        // Sin `oauthAccount`: el archivo está pero no hay sesión.
        elArchivo().writeAsStringSync(
          jsonEncode({'mcpServers': <String, Object?>{}}),
        );
        expect((await fuente.datosDe(casa.path)).correo, isNull);

        // Y un archivo a medio escribir vale lo mismo que no saberlo: esto no
        // puede tumbar la pantalla que lo enseña.
        elArchivo().writeAsStringSync('{a medias');
        expect((await fuente.datosDe(casa.path)).correo, isNull);
      },
    );

    // Un valor que no es un correo no se enseña como si lo fuera: lo que sale
    // en pantalla tiene que poder reconocerse.
    test('lo que no parece un correo no cuenta', () async {
      elArchivo().writeAsStringSync(
        jsonEncode({
          'oauthAccount': {'emailAddress': 'sin-arroba'},
        }),
      );

      expect(
        (await const ClaudeProfilesDataSource().datosDe(casa.path)).correo,
        isNull,
      );
    });
  });

  // 🔴 **La regla entera, y sale de las dos mitades del mismo reporte:** la de
  // siempre se enseña **solo si no hay perfiles con nombre**. Quien no creó
  // ninguno —lo normal si instalaste Claude y nada más— tiene que poder ver la
  // suya; y quien sí los creó lo dijo claro: «en mi caso no hay que meter la de
  // General, porque mis perfiles son WORK y PRIVATE».
  group('qué cuentas se enseñan', () {
    late Directory casa;

    setUp(() => casa = Directory.systemTemp.createTempSync('home'));
    tearDown(() => casa.deleteSync(recursive: true));

    ClaudeProfilesDataSource enEstaCasa() =>
        ClaudeProfilesDataSource(home: casa.path);

    void creaLaCuenta(String nombre, {String? organizacion}) {
      final dir = Directory('${casa.path}/$nombre')..createSync();
      File('${dir.path}/.claude.json').writeAsStringSync(
        jsonEncode({
          'oauthAccount': {
            'emailAddress': 'alguien@empresa.com',
            'organizationName': ?organizacion,
          },
        }),
      );
    }

    test('sin perfiles con nombre, la de siempre', () async {
      creaLaCuenta('.claude', organizacion: 'Empresa - Equipo');

      final cuentas = await enEstaCasa().paraMirar();

      expect(cuentas, hasLength(1));
      expect(cuentas.single.esLaDeSiempre, isTrue);
      expect(cuentas.single.correo, 'alguien@empresa.com');
    });

    test('con perfiles, solo los perfiles', () async {
      creaLaCuenta('.claude', organizacion: 'Empresa - Equipo');
      creaLaCuenta('.claude-work', organizacion: 'Empresa - Equipo');
      creaLaCuenta('.claude-private');

      final cuentas = await enEstaCasa().paraMirar();

      expect(cuentas.map((c) => c.name), [
        'private',
        'work',
      ], reason: 'la de siempre sobra: quien creó perfiles trabaja con ellos');
      expect(cuentas.any((c) => c.esLaDeSiempre), isFalse);
    });

    test('y si no hay ni home, no se inventa ninguna', () async {
      final cuentas = await ClaudeProfilesDataSource(
        home: '${casa.path}/no-existe',
      ).paraMirar();

      expect(cuentas.single.esLaDeSiempre, isTrue);
      expect(
        cuentas.single.correo,
        isNull,
        reason: 'existe como opción, pero no se sabe nada de ella',
      );
    });
  });

  group('quién es la de siempre', () {
    test('la reconoce por no tener nombre', () {
      const siempre = ClaudeProfile(
        path: '/Users/alguien/.claude',
        name: '',
        signedIn: true,
      );
      const conNombre = ClaudeProfile(
        path: '/Users/alguien/.claude-work',
        name: 'work',
        signedIn: true,
      );

      expect(siempre.esLaDeSiempre, isTrue);
      expect(conNombre.esLaDeSiempre, isFalse);
    });

    test('y su directorio sale del home', () {
      expect(ClaudeProfile.elDeSiempre(), endsWith('/.claude'));
      expect(
        ClaudeProfile.nameFromPath(ClaudeProfile.elDeSiempre()),
        isNull,
        reason: 'no tiene nombre: es la ausencia de perfil',
      );
    });
  });
}

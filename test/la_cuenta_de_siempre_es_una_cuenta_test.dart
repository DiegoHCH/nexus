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

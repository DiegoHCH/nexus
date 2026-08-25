import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/platform/binario_en_el_path.dart';
import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/features/assistant/domain/usecases/mcp_permissions.dart';
import 'package:nexus/features/superpowers/domain/entities/mcp_catalog.dart';
import 'package:nexus/features/superpowers/domain/usecases/mcp_command.dart';

/// Maestro: manejar una app móvil en un emulador desde un encargo.
///
/// Lo que se prueba aquí no es que Maestro funcione —eso lo dirá el emulador—
/// sino las tres costuras por las que esto se rompe en silencio: el PATH que no
/// lo encuentra, el `run_on_cloud` que sube el binario de la app a un servidor
/// ajeno desde una carpeta de solo lectura, y un catálogo que ofrece instalar
/// algo que no está.
void main() {
  group('la entrada del catálogo', () {
    final maestro = McpCatalog.entries.firstWhere(
      (e) => e.name == 'maestro',
    );

    test('se instala como servidor de comando, no como URL', () {
      // `maestro mcp` habla por stdio. Puesto como URL, `claude mcp add` lo
      // registraría con transporte http y no contestaría nunca.
      expect(maestro.command, ['maestro', 'mcp']);
      expect(maestro.url, isNull);
    });

    test('el nombre le vale al CLI', () {
      // Estos argumentos acaban en un proceso: un nombre que no pasa por aquí no
      // falla, hace otra cosa.
      expect(McpCommand.validName('maestro'), isTrue);
      expect(
        McpCommand.add(name: 'maestro', command: maestro.command),
        ['mcp', 'add', '-s', 'user', 'maestro', '--', 'maestro', 'mcp'],
      );
    });

    test('es el único que dice cómo instalarse, y lo dice porque hace falta', () {
      // Los de `npx` se bajan solos en la primera ejecución; este no. Si algún
      // día se añade otro binario previo sin instrucciones, esta prueba no lo
      // pilla — lo que fija es que el que las necesita las tenga.
      expect(maestro.comoSeInstala, isNotNull);
      expect(maestro.comoSeInstala, contains('get.maestro.mobile.dev'));

      for (final otro in McpCatalog.entries.where((e) => e.name != 'maestro')) {
        expect(
          otro.comoSeInstala,
          isNull,
          reason: '${otro.name} no necesita instalación previa: es npx o una URL',
        );
      }
    });
  });

  group('el PATH con el que la app lanza procesos', () {
    test('trae el directorio donde Maestro se instala', () {
      // **La costura que habría costado la tarde.** El instalador de Maestro deja
      // el binario en `~/.maestro/bin` y añade ese directorio editando el perfil
      // de la shell, que una app de escritorio no lee: en una terminal `maestro`
      // está y aquí no. El servidor se registraría bien para fallar al arrancar.
      expect(ClaudeEnvironment.forTools()['PATH'], contains('/.maestro/bin'));
    });

    test('Homebrew sigue ganando', () {
      // Quien lo instaló por el tap lo tiene en `/opt/homebrew/bin`, y ahí manda
      // el que puso a propósito. El orden es la mitad de lo que hace esa lista.
      final path = ClaudeEnvironment.forTools()['PATH']!;
      expect(
        path.indexOf('/opt/homebrew/bin'),
        lessThan(path.indexOf('/.maestro/bin')),
      );
    });
  });

  group('encontrar el binario', () {
    test('recorre el PATH en orden y devuelve el primero que existe', () {
      final ruta = BinarioEnElPath.resolver(
        'maestro',
        path: '/vacio:/opt/homebrew/bin:/casa/.maestro/bin',
        existe: (r) =>
            r == '/opt/homebrew/bin/maestro' || r == '/casa/.maestro/bin/maestro',
      );

      expect(ruta, '/opt/homebrew/bin/maestro');
    });

    test('null cuando no está en ninguno', () {
      expect(
        BinarioEnElPath.resolver(
          'maestro',
          path: '/uno:/dos',
          existe: (_) => false,
        ),
        isNull,
      );
    });

    test('un nombre con barra ya es una ruta y no se busca', () {
      // El sistema no busca en el PATH lo que trae barra, y esto tampoco: si lo
      // hiciera, probaría rutas como `/uno//casa/maestro`.
      final consultadas = <String>[];
      final ruta = BinarioEnElPath.resolver(
        '/casa/maestro',
        path: '/uno:/dos',
        existe: (r) {
          consultadas.add(r);
          return true;
        },
      );

      expect(ruta, '/casa/maestro');
      expect(consultadas, ['/casa/maestro']);
    });

    test('un PATH con huecos no genera rutas de la raíz', () {
      // `''.split(':')` da `['']`, y sin el filtro eso pregunta por `/maestro`.
      expect(
        BinarioEnElPath.resolver(
          'maestro',
          path: '::',
          existe: (r) => r == '/maestro',
        ),
        isNull,
      );
    });
  });

  group('lo que Maestro no puede hacer desde una carpeta de solo lectura', () {
    test('subir la app a la nube está negado', () {
      // Todo lo suyo es local salvo esta: `run_on_cloud` **sube el binario de la
      // app** a los servidores de mobile.dev. Una carpeta que promete no escribir
      // no puede mandar fuera lo que compiló.
      expect(
        McpPermissions.escrituraDeFuera,
        contains('mcp__maestro__run_on_cloud'),
      );
    });

    test('y el servidor sigue permitido, que es el punto', () {
      // La denegación gana al permiso —medido—, así que quitarle una herramienta
      // no cuesta el resto: mirar la pantalla y correr un flow en el emulador de
      // casa siguen valiendo en una carpeta que no escribe. Si esto se cayera,
      // Maestro dejaría de servir justo donde más se usa —un repo ajeno que se
      // abre en solo lectura para mirarlo.
      final perfil = Directory.systemTemp.createTempSync('perfil-maestro');
      addTearDown(() => perfil.deleteSync(recursive: true));
      File('${perfil.path}/.claude.json').writeAsStringSync(
        '{"mcpServers": {"maestro": {"command": "maestro"}}}',
      );

      expect(
        McpPermissions.permitidosPara(perfil.path, puedeEscribir: false),
        contains('maestro'),
      );
    });
  });
}

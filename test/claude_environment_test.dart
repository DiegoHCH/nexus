import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/platform/claude_environment.dart';

/// Estas pruebas no fijan el entorno real —`Platform.environment` es de solo
/// lectura— así que comprueban **invariantes** entre las dos salidas, que es lo
/// que puede romperse al tocar aquí.
void main() {
  test('el PATH de una herramienta trae delante lo que una GUI no hereda', () {
    final path = ClaudeEnvironment.forTools()['PATH']!;

    // Delante y no detrás: si el sistema trae otro `git` o `claude` más viejo,
    // gana el de Homebrew, que es el que el usuario instaló a propósito.
    expect(path, startsWith('/opt/homebrew/bin:/usr/local/bin'));
  });

  test('el perfil no vuelve a tocar el PATH que ya montó forTools', () {
    // La regresión que acecha al extraer `forTools`: dejar el bloque del PATH
    // también en `forProfile` y añadir los directorios dos veces.
    expect(
      ClaudeEnvironment.forProfile(null)['PATH'],
      ClaudeEnvironment.forTools()['PATH'],
    );
  });

  // 🔴 **El bug que bloqueó a la primera persona ajena que instaló Nexus.**
  //
  // Aquí había un `env['CLAUDE_CONFIG_DIR'] ??= '$home/.claude'` puesto por
  // prudencia — «en último caso, el de fábrica»— y hacía lo contrario de lo que
  // pretendía: **nombrar el directorio por defecto cambia de dónde lee las
  // credenciales**. Claude Code guarda el token en el llavero con un nombre que
  // depende de si la variable está puesta:
  //
  //     sin la variable   → «Claude Code-credentials»
  //     con la variable   → «Claude Code-credentials-<sha256(ruta)[:8]>»
  //
  // Dos almacenes distintos **aunque la ruta sea la misma**. La app decía
  // «ninguna cuenta tiene sesión abierta» a alguien cuyo `claude auth status`
  // contestaba `loggedIn: true` en su terminal.
  //
  // La prueba se escribe contra `Platform.environment` y no contra un valor
  // fijo, y es deliberado: en la máquina donde se escribió esto la variable
  // **está exportada**, así que un `isNull` pasaría en CI y fallaría en local —
  // exactamente la asimetría que escondió el bug. Lo que hay que fijar no es
  // «no hay variable»: es **«no se inventa ninguna»**.
  test('sin perfil no se inventa una cuenta: se respeta lo que haya', () {
    expect(
      ClaudeEnvironment.forProfile(null)['CLAUDE_CONFIG_DIR'],
      Platform.environment['CLAUDE_CONFIG_DIR'],
      reason:
          'poner el directorio por defecto a mano cambia el llavero que lee',
    );
  });

  test('la cuenta se fija cuando se pide, y solo entonces', () {
    expect(
      ClaudeEnvironment.forProfile(
        '/tmp/perfil-de-prueba',
      )['CLAUDE_CONFIG_DIR'],
      '/tmp/perfil-de-prueba',
    );

    // `git` no sabe qué es una cuenta de Claude: lo que se le pasa a una
    // herramienta cualquiera no lleva nada de eso encima.
    final tools = ClaudeEnvironment.forTools();
    final profile = ClaudeEnvironment.forProfile('/tmp/perfil-de-prueba');
    expect(
      tools['CLAUDE_CONFIG_DIR'],
      isNot('/tmp/perfil-de-prueba'),
      reason: 'forTools no debe arrastrar el perfil que pidió forProfile',
    );
    expect(profile['CLAUDE_CONFIG_DIR'], isNot(tools['CLAUDE_CONFIG_DIR']));
  });
}

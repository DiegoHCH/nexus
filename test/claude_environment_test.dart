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

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/claude_errand.dart';

/// El único caso de uso del dominio que estaba **entero sin cubrir**, y salió
/// mirando la cobertura por capas en vez del número agregado.
///
/// Traduce lo que pide el modelo de voz a la instrucción que recibe Claude, así
/// que un fallo aquí no da un error: da un encargo distinto del que se pidió.

void main() {
  group('el nombre de una skill', () {
    // El comentario del propio archivo lo cuenta: en la primera prueba el
    // modelo devolvió `revisar_stocks` con guion bajo aunque se le pidió otra
    // cosa. Corregirlo aquí es más barato que confiar en que acierte.
    test('lo que el modelo devuelve mal se corrige', () {
      expect(ClaudeErrand.skillName('revisar_stocks'), 'revisar-stocks');
      expect(ClaudeErrand.skillName('Revisar Stocks'), 'revisar-stocks');
      expect(ClaudeErrand.skillName('  REVISAR   stocks  '), 'revisar-stocks');
    });

    test('lo que no cabe en una carpeta se cae', () {
      expect(ClaudeErrand.skillName('revisar/stocks!'), 'revisarstocks');
      expect(ClaudeErrand.skillName('«acentos» y ñ'), 'acentos-y');
    });

    // `null` y no una carpeta llamada `-` o vacía: con un nombre inservible, lo
    // que toca es no lanzar el encargo.
    test('lo que se queda en nada no es un nombre', () {
      for (final malo in [null, '', '   ', '---', '¿?¡!']) {
        expect(ClaudeErrand.skillName(malo), isNull, reason: '«$malo»');
      }
    });
  });

  group('qué encargo sale de cada herramienta', () {
    test('pasarle trabajo es reenviar la frase', () {
      expect(
        ClaudeErrand.forTool(ClaudeErrand.askTool, {
          'instruccion': '  mira el historial  ',
        }),
        'mira el historial',
      );
    });

    // Mejor decírselo al modelo que inventarse un encargo con lo que haya
    // llegado: un encargo inventado sí se ejecuta.
    test('una herramienta que no se conoce no produce encargo', () {
      expect(ClaudeErrand.forTool('lo_que_sea', const {}), isNull);
    });

    test('crear una skill es un procedimiento, no una frase', () {
      final encargo = ClaudeErrand.forTool(ClaudeErrand.skillTool, {
        'nombre': 'revisar_stocks',
        'para_que': 'mirar el inventario antes de pedir',
      })!;

      // El nombre ya normalizado, y en la ruta donde de verdad va.
      expect(encargo, contains('.claude/skills/revisar-stocks/SKILL.md'));
      expect(encargo, contains('mirar el inventario antes de pedir'));
      // Lo que el tracker pedía: que la genere, que la compruebe y que diga
      // cómo se invoca.
      expect(encargo, contains('frontmatter'));
      expect(encargo, contains('Comprueba lo que escribiste'));
      // Y que no lo intente con la carpeta en solo lectura, que acabaría en un
      // permiso denegado a mitad en vez de en un «no puedo».
      expect(encargo, contains('solo lectura'));
    });

    test('sin nombre o sin para qué, no hay encargo', () {
      expect(
        ClaudeErrand.forTool(ClaudeErrand.skillTool, {'para_que': 'algo'}),
        isNull,
      );
      expect(
        ClaudeErrand.forTool(ClaudeErrand.skillTool, {
          'nombre': 'una-skill',
          'para_que': '   ',
        }),
        isNull,
      );
    });
  });
}

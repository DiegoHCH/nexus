import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/attached_files.dart';

void main() {
  group('lo que se añade', () {
    test('se conserva el orden en que se soltaron', () {
      expect(AttachedFiles.add(const ['/a.png'], ['/b.pdf', '/c.txt']), [
        '/a.png',
        '/b.pdf',
        '/c.txt',
      ]);
    });

    // Arrastrar dos veces el mismo archivo es un accidente corriente, y lo que
    // no puede salir de él es pedirle a Claude que lo lea dos veces.
    test('el mismo archivo no entra dos veces', () {
      expect(AttachedFiles.add(const ['/a.png'], ['/a.png']), ['/a.png']);
    });
  });

  group('el nombre que se enseña', () {
    test('es el último tramo de la ruta', () {
      expect(AttachedFiles.name('/Users/x/Escritorio/mock.png'), 'mock.png');
    });

    // Una carpeta soltada llega con la barra final y sin esto se quedaría sin
    // nombre que enseñar.
    test('una carpeta se nombra por su carpeta, no por el vacío del final', () {
      expect(AttachedFiles.name('/Users/x/proyecto/'), 'proyecto');
    });
  });

  group('el encargo que se manda', () {
    test('sin adjuntos, el texto va tal cual', () {
      expect(
        AttachedFiles.instruction('arregla esto', const [], label: 'Adjuntos:'),
        'arregla esto',
      );
    });

    // Cada ruta en su línea porque las hay con espacios: en una lista separada
    // por comas no habría forma de saber dónde acaba una.
    test('con adjuntos, las rutas van detrás y una por línea', () {
      final salida = AttachedFiles.instruction(
        'compara estos dos',
        const ['/Users/x/Mis cosas/uno.png', '/Users/x/dos.png'],
        label: 'Archivos adjuntos:',
      );

      expect(salida, '''
compara estos dos

Archivos adjuntos:
- /Users/x/Mis cosas/uno.png
- /Users/x/dos.png''');
    });

    // Soltar un archivo y dar a enviar es un gesto legítimo: obligar a escribir
    // «mira esto» sería pedir que se diga lo que el gesto ya dijo.
    test('sin texto, la lista es la petición', () {
      expect(
        AttachedFiles.instruction('  ', const ['/a.png'], label: 'Adjuntos:'),
        'Adjuntos:\n- /a.png',
      );
    });
  });
}

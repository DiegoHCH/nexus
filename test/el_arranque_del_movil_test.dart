import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// El `main` del teléfono, vigilado leyendo el archivo.
//
// **Es una prueba rara a propósito**, y existe por un fallo concreto: el `main` del
// móvil pedía la versión del paquete —un canal de plataforma— antes de
// `WidgetsFlutterBinding.ensureInitialized()`. Eso lanza «Binding has not yet been
// initialized», y en el teléfono se ve como una pantalla negra y nada más.
//
// Las 648 pruebas de entonces estaban en verde, y ninguna podía verlo: el arnés de
// pruebas inicializa su propio binding, así que ese `main` **no se ejecuta nunca**
// ahí. Lo destapó arrancar la app en un teléfono de verdad.
//
// Así que se ata leyendo el texto. No es elegante; es lo único que cubre el hueco
// entre «las pruebas pasan» y «la app arranca».
void main() {
  final fuente = File('lib/main_movil.dart').readAsStringSync();

  /// El código **sin comentarios**.
  ///
  /// Hace falta porque la primera versión de esta prueba fallaba con el arreglo ya
  /// puesto: el comentario que explica por qué hay que inicializar el binding
  /// menciona `PackageInfo`, y la prueba encontraba esa mención —antes de la
  /// llamada— y la contaba como uso. Una prueba que se cree los comentarios vigila
  /// la prosa, no el código.
  String sinComentarios(String codigo) => codigo
      .split('\n')
      .map((linea) {
        final corte = linea.indexOf('//');
        return corte < 0 ? linea : linea.substring(0, corte);
      })
      .join('\n');

  test('el main inicializa el binding antes de tocar la plataforma', () {
    final codigo = sinComentarios(fuente);
    final cuerpo = codigo.substring(codigo.indexOf('Future<void> main()'));
    final hastaRunApp = cuerpo.substring(0, cuerpo.indexOf('runApp('));

    // Todo lo que hable con el sistema antes de `runApp` necesita el binding. Si se
    // añade otro —preferencias, llavero, permisos— esta lista tiene que crecer, y el
    // fallo de no crecerla es una pantalla negra.
    const canalesDePlataforma = [
      'PackageInfo',
      'SharedPreferences',
      'MethodChannel',
    ];
    final usados = canalesDePlataforma.where(hastaRunApp.contains).toList();

    if (usados.isEmpty) return;

    final binding = hastaRunApp.indexOf(
      'WidgetsFlutterBinding.ensureInitialized()',
    );
    expect(
      binding,
      isNonNegative,
      reason:
          'el main usa $usados antes de runApp y no inicializa el binding: '
          'la app arranca en negro',
    );
    for (final canal in usados) {
      expect(
        binding,
        lessThan(hastaRunApp.indexOf(canal)),
        reason: '$canal se usa antes de inicializar el binding',
      );
    }
  });

  test('el main del escritorio no se toca desde aquí', () {
    // Los dos puntos de entrada son distintos a propósito —el del escritorio arranca
    // atajos, ventana y autoactualizado, y nada de eso existe en un teléfono— y esta
    // prueba solo habla del móvil. Se comprueba que siguen siendo dos, porque si
    // alguien los une, lo que esta prueba vigila deja de estar donde mira.
    expect(File('lib/main.dart').existsSync(), isTrue);
    expect(fuente.contains('NexusMovil'), isTrue);
  });
}

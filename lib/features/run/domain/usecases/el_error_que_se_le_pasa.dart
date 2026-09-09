import 'package:nexus/features/run/domain/usecases/el_error_que_pinta_la_app.dart';

/// El último error de la app, sacado del registro y listo para pasárselo a
/// Claude.
///
/// 🔴 **Cierra un círculo que estaba medio construido.** Nexus ya oye los
/// errores del framework —[ElErrorQuePintaLaApp]— y ya sabe pasar encargos a la
/// carpeta de un proyecto; lo que no había era el paso de uno a otro. El puente
/// entre correr y encargar iba **en un solo sentido**: al terminar un encargo se
/// recarga la app, y al revés nada. Así que la app se rompía, lo veías, y
/// arreglarlo pasaba por copiar el bloque a mano — que es exactamente donde se
/// pierde la parte que importa, medido dos días seguidos con un `git push` mal
/// retranscrito.
///
/// Aquí solo vive **qué se le manda**: el bloque y la frase. Quién lo lleva es
/// el despacho de carpeta, que ya sabe buscar la conversación, abrirla si no
/// está y respetar el tope de escritura.
abstract final class ElErrorQueSeLePasa {
  /// Cuántas líneas de un bloque se llevan como mucho.
  ///
  /// Una traza de Flutter son treinta o cuarenta líneas y las diez primeras ya
  /// dicen dónde: el resto es el framework llamándose a sí mismo. Se corta
  /// porque esto entra en el prompt de un encargo, y el prompt se paga.
  static const tope = 24;

  /// El último error del registro, con las líneas que lo acompañan, o `null` si
  /// ahí no hay ninguno.
  ///
  /// Se busca **de abajo arriba**: lo que se quiere pasar es lo último que se
  /// rompió, no lo primero. Y arrastra lo que va detrás —la traza, el «relevant
  /// error-causing widget»— hasta topar con otro error o con el tope: sin la
  /// traza, un «Bad state» suelto no dice dónde mirar.
  static String? deLasLineas(List<String> lineas) {
    final desde = lineas.lastIndexWhere(ElErrorQuePintaLaApp.pintaMal);
    if (desde < 0) return null;

    final bloque = <String>[lineas[desde]];
    for (var i = desde + 1; i < lineas.length && bloque.length < tope; i++) {
      // Otro error empieza su propio bloque: pasar dos mezclados es pedirle a
      // Claude que adivine cuál se arregla.
      if (ElErrorQuePintaLaApp.pintaMal(lineas[i])) break;
      bloque.add(lineas[i]);
    }
    return bloque.join('\n').trimRight();
  }

  /// El encargo entero: qué se pide y el bloque tal cual.
  ///
  /// **El bloque va literal y al final.** Resumirlo sería tirar justo lo que
  /// hace falta —el archivo y la línea—, y ponerlo delante deja la instrucción
  /// enterrada bajo treinta líneas de traza.
  ///
  /// El texto de la petición lo pone quien llama, en el idioma elegido: esto es
  /// dominio.
  static String elEncargo({required String peticion, required String bloque}) =>
      '$peticion\n\n$bloque';
}

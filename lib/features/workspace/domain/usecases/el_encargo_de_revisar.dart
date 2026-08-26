import 'package:nexus/features/workspace/domain/usecases/reglas_declaradas.dart';

/// El encargo que se le manda a Claude para revisar el diff contra las reglas de su capa.
///
/// **Es lo que el gate no puede ver.** Un `flutter test` dice si el código funciona; no
/// dice si la validación acabó en el widget en vez de en el dominio. Eso solo lo puede
/// leer alguien con la regla delante, y la regla la declara el propio repo.
///
/// Se arma aquí y no se le pide a Claude que lo averigüe por su cuenta, por lo mismo que
/// Nexus carga las reglas en vez de remitir a ellas: encomendar la lectura se cumple la
/// mitad de las veces, y una revisión que a veces no mira la regla no es una revisión.
///
/// **No produce un veredicto ni lo pide.** Se piden hallazgos, con el archivo y la regla
/// que los sostiene. Un «pasa / no pasa» de un modelo se acabaría leyendo como un segundo
/// gate, y no lo es: el gate mide, esto lee.
abstract final class ElEncargoDeRevisar {
  /// Cuántos archivos se nombran antes de resumir. Una rama con doscientos archivos
  /// tocados no da un encargo mejor por listarlos todos, da uno que no cabe.
  static const topeDeArchivos = 40;

  /// El texto del encargo, o `null` si no hay nada que revisar.
  ///
  /// Sin archivos tocados no hay diff, y sin reglas de capa que encajen tampoco hay nada
  /// que esto pueda añadir a lo que ya hace el gate. En los dos casos se contesta que no,
  /// en vez de mandar un encargo que va a volver diciendo que no había nada.
  static String? texto({
    required List<String> archivos,
    required List<ReglaDeclarada> reglas,
    String? rama,
  }) {
    if (archivos.isEmpty) return null;
    final deCapa = reglas.where((regla) => !regla.siempre).toList();
    final aplican = ReglasDeclaradas.paraArchivos(deCapa, archivos);
    if (aplican.isEmpty) return null;

    final listados = archivos.take(topeDeArchivos).toList();
    final resto = archivos.length - listados.length;

    final texto = StringBuffer()
      ..writeln(
        'Revisa lo que llevo tocado en esta rama contra las reglas que el propio '
        'repositorio declara para cada capa. No corras las pruebas ni cambies nada: '
        'esto es una lectura.',
      );
    if (rama != null && rama.isNotEmpty) {
      texto.writeln('\nRama: $rama');
    }

    texto.writeln('\nArchivos tocados (${archivos.length}):');
    for (final archivo in listados) {
      texto.writeln('- $archivo');
    }
    if (resto > 0) {
      // Lo que se recorta se dice. Un encargo que lista treinta de doscientos sin avisar
      // se lee como «esto es todo lo que hay».
      texto.writeln('- …y $resto más, que no caben en este encargo.');
    }

    texto.writeln('\nLas reglas que aplican a esos archivos:');
    for (final regla in deCapa) {
      if (!aplican.contains(regla.ruta)) continue;
      final porQue = ReglasDeclaradas.archivosDe(
        regla.patron!,
        archivos,
      ).take(3).join(', ');
      texto.writeln('- ${regla.ruta}  (por: $porQue)');
    }

    texto
      ..writeln(
        '\nLee cada una de esas reglas y después el diff (`git diff HEAD`, y los '
        'archivos nuevos que no salgan en él). Para cada cosa que no las cumpla, dime '
        'el archivo, qué regla se salta y por qué.',
      )
      ..writeln(
        '\nSi no encuentras nada, dilo en una línea. No hace falta un informe: hace '
        'falta la lista de lo que hay que arreglar, y nada más.',
      );
    return texto.toString();
  }
}

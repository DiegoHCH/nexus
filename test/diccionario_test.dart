import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// La red debajo del diccionario.
//
// Son 506 textos con **tres implementaciones a mano**, repartidos en ocho
// archivos por feature. Añadir uno son tres ediciones, y el compilador solo
// obliga a que existan: no a que interpolen ni a que digan lo mismo.
//
// Caso de fallo, y ocurrió el 18 de agosto: al añadir cuatro textos se escapó
// una interpolación y el inglés habría impreso `$folder` tal cual, con el nombre
// de la carpeta perdido en medio de una frase sobre privacidad. `flutter analyze`
// pasó limpio, porque para el analizador es una cadena válida.
//
// Esto lee **el propio archivo fuente**. No hace falta reflexión —una prueba
// puede abrir el fuente— y así se cubren cosas que ningún tipo puede expresar.
void main() {
  // **Los ocho, no uno.** Esto leía `nexus_strings.dart` a secas, y el día que
  // el diccionario se partió por features habría encontrado cero
  // implementaciones y pasado sin mirar nada — que es justo el fallo contra el
  // que avisa la primera prueba de aquí. Se lee la carpeta entera para que
  // añadir un archivo no lo deje fuera por olvido.
  final fuentes = Directory('lib/core/i18n/strings')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('_strings.dart'))
      .toList();

  /// Cada implementación: su nombre, sus parámetros y su cuerpo.
  ///
  /// Se salta las declaraciones de la clase abstracta —no tienen `=>`— y coge
  /// tanto los `String get x =>` como los `String x(int y) =>`.
  final cuerpos = RegExp(
    r'  String (?:get )?(\w+)(\([^)]*\))? =>(.*?);\n',
    dotAll: true,
  ).allMatches(fuentes.map((f) => f.readAsStringSync()).join('\n')).toList();

  // Antes de comprobar nada: que de verdad se haya leído algo.
  //
  // Sin esto, el día que alguien reordene el archivo o cambie el formato, el
  // patrón deja de encontrar implementaciones y **las tres pruebas de abajo
  // pasan sin mirar nada**. Un guardia que se queda ciego y sigue diciendo que
  // todo va bien es peor que no tener guardia.
  test('el archivo se lee y hay implementaciones que revisar', () {
    expect(
      fuentes,
      isNotEmpty,
      reason: 'no se encontró ningún archivo de textos',
    );
    expect(
      cuerpos.length,
      greaterThan(500),
      reason:
          'se encontraron ${cuerpos.length}: el patrón dejó de reconocer el '
          'archivo, así que las demás pruebas de aquí no están comprobando nada',
    );
  });

  // Partirlo abre un hueco que antes no existía: un archivo nuevo con sus tres
  // mixins compila perfectamente y **no lo usa nadie**. No hay error, no hay
  // aviso; los textos simplemente no existen para la app. Esto lo cierra.
  test('los ocho archivos están enchufados en la sombrilla', () {
    final sombrilla = File(
      'lib/core/i18n/nexus_strings.dart',
    ).readAsStringSync();
    final sueltos = <String>[];

    for (final archivo in fuentes) {
      final nombre = RegExp(
        r'^mixin (\w+Strings) \{',
        multiLine: true,
      ).firstMatch(archivo.readAsStringSync())?.group(1);
      if (nombre == null) {
        sueltos.add('${archivo.path}: no declara un mixin de textos');
        continue;
      }
      for (final quien in [nombre, '${nombre}Es', '${nombre}En']) {
        // Con límites de palabra a los dos lados: `ArranqueStrings` va el
        // último de su lista y le sigue una llave, no una coma — y así tampoco
        // se confunde con `ArranqueStringsEs`.
        if (!sombrilla.contains(RegExp('\\b$quien\\b'))) {
          sueltos.add('$quien no se mezcla en NexusStrings');
        }
      }
    }

    expect(
      sueltos,
      isEmpty,
      reason:
          'un archivo de textos que nadie mezcla compila igual y sus textos no '
          'existen para la app: ${sueltos.join(' · ')}',
    );
  });

  test('cada texto con parámetro lo usa de verdad', () {
    final sinUsar = <String>[];

    for (final cuerpo in cuerpos) {
      final params = (cuerpo.group(2) ?? '').replaceAll(RegExp(r'[()]'), '');
      final nombres = params
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .map((p) => p.split(' ').last);

      final texto = cuerpo.group(3)!;
      for (final nombre in nombres) {
        if (!texto.contains('\$$nombre') && !texto.contains('\${$nombre')) {
          sinUsar.add('${cuerpo.group(1)} no usa «$nombre»');
        }
      }
    }

    expect(
      sinUsar,
      isEmpty,
      reason:
          'un texto que declara un parámetro y no lo interpola pierde el dato '
          'justo donde hacía falta: ${sinUsar.join(' · ')}',
    );
  });

  test('ninguna interpolación va escapada', () {
    // Es el error que se cometió: `\$folder` compila, pasa el análisis y
    // imprime el nombre de la variable en la cara del usuario.
    final escapadas = cuerpos
        .where((c) => c.group(3)!.contains(r'\$'))
        .map((c) => c.group(1)!)
        .toList();

    expect(
      escapadas,
      isEmpty,
      reason:
          'imprimirían el literal en vez del valor: ${escapadas.join(', ')}',
    );
  });

  test('no hay palabras pegadas al unir literales de varias líneas', () {
    // Un texto largo se parte en varios literales seguidos y el espacio se pone
    // a mano al final de cada uno. Olvidarlo pega la última palabra con la
    // primera de la línea siguiente —«todoslos»— y no lo ve nadie hasta que
    // aparece en pantalla.
    //
    // Los saltos `\n` explícitos se excluyen: ahí la unión es a propósito.
    final pegadas = <String>[];
    final union = RegExp(
      r"(?<!\\n)(?<!\\)[A-Za-zÀ-ÿ,;:)]'\s*\n\s*'[A-Za-zÀ-ÿ¿¡]",
    );

    for (final cuerpo in cuerpos) {
      if (union.hasMatch(cuerpo.group(3)!)) pegadas.add(cuerpo.group(1)!);
    }

    expect(
      pegadas,
      isEmpty,
      reason:
          'falta un espacio al final de un literal en: ${pegadas.join(', ')}',
    );
  });
}

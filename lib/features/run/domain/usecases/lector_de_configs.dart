import 'dart:convert';

import 'package:nexus/features/run/domain/entities/config_de_arranque.dart';

/// Leer el `launch.json` de un proyecto y traducirlo a algo lanzable.
abstract final class LectorDeConfigs {
  /// Las configuraciones de Flutter que declara el archivo.
  ///
  /// Se queda solo con `type: dart` y `request: launch`: un `launch.json` real
  /// lleva también configuraciones de `attach` y, en un monorepo, de otros
  /// lenguajes. Ofrecer una de esas como forma de arrancar la app sería ofrecer
  /// un fallo.
  static List<ConfigDeArranque> leer(String jsonc) {
    final Object? leido;
    try {
      leido = jsonDecode(sinComentarios(jsonc));
    } on FormatException {
      return const [];
    }
    if (leido is! Map) return const [];

    final configuraciones = leido['configurations'];
    if (configuraciones is! List) return const [];

    return [
      for (final entrada in configuraciones)
        if (entrada is Map)
          if (entrada['type'] == 'dart')
            if ((entrada['request'] ?? 'launch') == 'launch')
              ConfigDeArranque(
                nombre: '${entrada['name'] ?? 'sin nombre'}',
                entry: entrada['program'] as String?,
                modo: '${entrada['flutterMode'] ?? 'debug'}',
                args: [
                  for (final a in (entrada['args'] as List?) ?? const []) '$a',
                ],
              ),
    ];
  }

  /// Los argumentos de `flutter run` para una configuración.
  ///
  /// [proyecto] hace falta para sustituir las variables del editor. No es
  /// teórico: una configuración real de las que hay por ahí lleva
  /// `--dart-define PROJECT_ROOT=${workspaceFolder}`, y sin sustituirla se le
  /// pasaría a la app el texto literal.
  static List<String> argumentos(
    ConfigDeArranque config, {
    required String proyecto,
  }) => [
    if (config.entry case final entry?) ...['-t', _sustituye(entry, proyecto)],
    // `debug` no lleva bandera: es lo que hace `flutter run` sin más.
    if (config.modo == 'profile') '--profile',
    if (config.modo == 'release') '--release',
    for (final a in config.args) _sustituye(a, proyecto),
  ];

  static String _sustituye(String valor, String proyecto) => valor
      .replaceAll(r'${workspaceFolder}', proyecto)
      .replaceAll(r'${workspaceRoot}', proyecto);

  /// Quita los comentarios y las comas colgantes de un JSON con concesiones.
  ///
  /// **Hace falta porque los `launch.json` de verdad los llevan**: el de un
  /// proyecto real que se miró para esto tiene comentarios `//`, y un
  /// `jsonDecode` a pelo lanza en la primera línea.
  ///
  /// Lo que **no** se puede hacer es borrar todo lo que vaya detrás de `//` con
  /// una expresión regular, y por eso esto recorre el texto carácter a carácter:
  /// una barra doble dentro de una cadena es lo más normal del mundo —cualquier
  /// `https://` en un `--dart-define`— y un limpiador ingenuo se comería el resto
  /// de la línea, dejando un JSON roto y una lista vacía sin explicación.
  ///
  /// Se respetan también las comillas escapadas: `"lo que \" lleva dentro"`.
  static String sinComentarios(String texto) {
    final salida = StringBuffer();
    var dentroDeCadena = false;
    var escapado = false;
    var i = 0;

    while (i < texto.length) {
      final c = texto[i];

      if (dentroDeCadena) {
        salida.write(c);
        if (escapado) {
          escapado = false;
        } else if (c == r'\') {
          escapado = true;
        } else if (c == '"') {
          dentroDeCadena = false;
        }
        i++;
        continue;
      }

      if (c == '"') {
        dentroDeCadena = true;
        salida.write(c);
        i++;
        continue;
      }

      // `//` hasta el fin de línea. El salto se conserva: quitarlo pegaría la
      // línea siguiente y podría juntar dos tokens.
      if (c == '/' && i + 1 < texto.length && texto[i + 1] == '/') {
        while (i < texto.length && texto[i] != '\n') {
          i++;
        }
        continue;
      }

      // `/* … */`, que también aparecen.
      if (c == '/' && i + 1 < texto.length && texto[i + 1] == '*') {
        i += 2;
        while (i + 1 < texto.length && !(texto[i] == '*' && texto[i + 1] == '/')) {
          i++;
        }
        i += 2;
        continue;
      }

      salida.write(c);
      i++;
    }

    // Las comas colgantes, ya sin comentarios que confundan. Fuera de cadenas no
    // hay forma de que una coma seguida de un cierre sea otra cosa.
    //
    // `replaceAllMapped` y no `replaceAll`: en Dart el reemplazo de `replaceAll`
    // es **texto literal**, así que un `r'$1'` no trae el grupo — escribe
    // «$1» tal cual y deja un JSON peor que el de entrada. Costó una prueba en
    // rojo descubrirlo, y es de las que no se ven leyendo.
    return salida.toString().replaceAllMapped(
      RegExp(r',(\s*[}\]])'),
      (m) => m.group(1)!,
    );
  }
}

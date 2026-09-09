import 'dart:convert';

import 'package:nexus/features/run/domain/entities/config_de_arranque.dart';
import 'package:nexus/features/run/domain/usecases/la_consola_de_la_app.dart';

/// Una configuración de arranque **tuya**, que no vive en el repositorio.
///
/// 🔴 **Pedida con un caso concreto:** el repo del trabajo trae
/// «Global66 (ci + Debug Dashboard)» pero no la misma con `prod`, ni la de
/// `profile`. Añadirla al `launch.json` es tocar un archivo **versionado y
/// compartido**: aparece en tu `git status`, viaja en cualquier commit
/// distraído y le cambia el menú del editor a todo el equipo. Y en un repo del
/// trabajo la regla es no comitear nada.
///
/// Así que las tuyas viven en el soporte de Nexus, se ofrecen en el mismo menú
/// que las del repo y **no tocan el repositorio**.
///
/// ## Lo que Nexus no se inventa
///
/// Los `--dart-define` que enciende la consola **no se cablean aquí**: se
/// **copian de la configuración del propio repo que ya la enciende**. En el
/// repo del trabajo esa configuración pasa dos —`ENABLE_DEBUG_SERVER=true` y
/// `PROJECT_ROOT=${workspaceFolder}`, el segundo para que el panel encuentre los
/// documentos— y adivinar solo el primero habría dado media consola con
/// aspecto de estar bien. El conocimiento sigue viviendo en el repo; Nexus lo
/// lee y lo lleva.
///
/// **Se copian solo los `--dart-define` sueltos, nunca los
/// `--dart-define-from-file`**: ese apunta al archivo de un entorno
/// —`config/ci.json`— y llevárselo a `prod` sería arrancar prod con la
/// configuración de ci. Es el fallo que este atajo tiene que evitar, no causar.
abstract final class LaConfigDeCasa {
  /// Lo que se le añade al nombre. Va al final y con la carpeta delante intacta
  /// para que las dos se lean seguidas en el desplegable: «Global66 (prod)» y
  /// «Global66 (prod) + consola».
  static const marca = ' + consola';

  /// La configuración del repo que ya enciende la consola, si hay alguna. De
  /// ella se aprenden los `--dart-define` que hacen falta.
  static ConfigDeArranque? laQueEnciendeLaConsola(
    List<ConfigDeArranque> configs,
  ) {
    for (final config in configs) {
      if (LaConsolaDeLaApp.laEnciende(config.args)) return config;
    }
    return null;
  }

  /// Si ya se puede duplicar [cual]: no tiene sentido copiar la que ya la trae.
  static bool sePuedeDuplicar(ConfigDeArranque cual) =>
      !LaConsolaDeLaApp.laEnciende(cual.args) && !cual.local;

  /// La copia de [cual] con la consola encendida, aprendiendo de [modelo].
  ///
  /// Sin modelo se pone lo mínimo —el flag— porque es lo único que Nexus sabe
  /// de verdad: es su propia constante, la que usa para saber si hay consola
  /// que abrir.
  static ConfigDeArranque conLaConsola(
    ConfigDeArranque cual, {
    ConfigDeArranque? modelo,
  }) {
    final defines = _defines(cual.args);
    final aprendidos = <String>[];
    for (final (clave, valor) in _defines(modelo?.args ?? const [])) {
      if (defines.any((suyo) => suyo.$1 == clave)) continue;
      aprendidos.addAll(['--dart-define', '$clave=$valor']);
    }
    if (!aprendidos.contains('${LaConsolaDeLaApp.elFlag}=true') &&
        !LaConsolaDeLaApp.laEnciende(aprendidos)) {
      aprendidos.addAll(['--dart-define', '${LaConsolaDeLaApp.elFlag}=true']);
    }

    return ConfigDeArranque(
      nombre: '${cual.nombre}$marca',
      entry: cual.entry,
      modo: cual.modo,
      args: [...cual.args, ...aprendidos],
      local: true,
    );
  }

  /// Los `--dart-define K=V` de una lista de argumentos, en pares.
  ///
  /// Se aceptan las dos formas porque las dos salen en `launch.json` de verdad:
  /// `--dart-define K=V` en dos entradas y `--dart-define=K=V` en una.
  static List<(String, String)> _defines(List<String> args) {
    final pares = <(String, String)>[];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String? crudo;
      if (arg == '--dart-define' && i + 1 < args.length) {
        crudo = args[i + 1];
        i++;
      } else if (arg.startsWith('--dart-define=')) {
        crudo = arg.substring('--dart-define='.length);
      }
      // `--dart-define-from-file` cae aquí y **se queda fuera**: apunta al
      // archivo de un entorno, y llevárselo a otro sería arrancar ese otro con
      // la configuración equivocada.
      if (crudo == null) continue;
      final igual = crudo.indexOf('=');
      if (igual <= 0) continue;
      pares.add((crudo.substring(0, igual), crudo.substring(igual + 1)));
    }
    return pares;
  }

  /// Las del repo y las tuyas, en un solo menú.
  ///
  /// Las tuyas al final y **sin pisar** a las del repo: si mañana alguien añade
  /// al `launch.json` una que se llama igual que tu copia, la del repo manda —es
  /// la compartida— y la tuya deja de ofrecerse en vez de tapar a la otra en
  /// silencio.
  static List<ConfigDeArranque> junta({
    required List<ConfigDeArranque> delRepo,
    required List<ConfigDeArranque> propias,
  }) {
    final nombres = {for (final config in delRepo) config.nombre};
    return [
      ...delRepo,
      for (final config in propias)
        if (nombres.add(config.nombre)) config,
    ];
  }

  /// El archivo de las tuyas, **con la forma de un `launch.json`**.
  ///
  /// A propósito: así se puede abrir con cualquier editor y retocar a mano —un
  /// `--dart-define` más, otro flavor— sin aprender un formato nuevo, y así lo
  /// lee el mismo [LectorDeConfigs] que lee el del repo. Un formato propio
  /// habría sido código nuevo para hacer lo mismo peor.
  static String comoArchivo(List<ConfigDeArranque> configs) {
    final json = const JsonEncoder.withIndent('  ').convert({
      'version': '0.2.0',
      'configurations': [
        for (final config in configs)
          {
            'name': config.nombre,
            'type': 'dart',
            'request': 'launch',
            'program': ?config.entry,
            'flutterMode': config.modo,
            'args': config.args,
          },
      ],
    });
    return '$json\n';
  }
}

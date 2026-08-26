/// Cómo se arranca la app: una de las configuraciones que el proyecto declara.
///
/// **Sale del `launch.json` del editor y no de un formato propio de Nexus**, y
/// esa es la decisión que sostiene todo lo demás. Quien trabaja en un repo ya
/// mantiene ahí sus flavors y sus `--dart-define`; pedirle que los repita en
/// otro sitio sería cobrarle un peaje por usar esta app, y tener dos listas que
/// se separan el día que alguien añada una.
class ConfigDeArranque {
  const ConfigDeArranque({
    required this.nombre,
    this.entry,
    this.modo = 'debug',
    this.args = const [],
  });

  /// Como se llama en el editor. Es lo que se enseña y lo que se elige.
  final String nombre;

  /// El `program` de la configuración, que acaba en `-t`. Opcional: sin él
  /// Flutter usa `lib/main.dart`.
  final String? entry;

  /// `debug`, `profile` o `release`.
  ///
  /// **No es un argumento**: se traduce a `--profile` o `--release`, y en debug no
  /// se pasa nada. Pasarlo tal cual sería inventar una bandera que no existe.
  final String modo;

  /// El resto, tal como lo escribió el editor: `--flavor`, los
  /// `--dart-define-from-file`, lo que sea. Nexus no los interpreta.
  final List<String> args;
}

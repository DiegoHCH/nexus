/// Una cuenta de prueba: con qué credenciales corre un flow.
///
/// **Existen varias y no es un capricho.** Medido en `global66/automated-test`: el
/// set de accesos rápidos del Home lo decide la cuenta —la peruana trae
/// `all_options`, la colombiana trae `breb` y no trae `all_options`—. Correr todo
/// con una sola cuenta deja rojos que no significan nada.
///
/// 🔴 **La lista es un dato, no código.** El `run.sh` del repo ya lo dice: agregar
/// una cuenta es «una línea en ACCOUNTS y el tag `acct-<x>` en los flows». Si acá
/// fueran dos constantes `pe` y `co`, agregar la tercera sería tocar Nexus y sacar
/// versión. Se guardan como lista editable justamente para que no lo sea.
class CuentaDePruebas {
  const CuentaDePruebas({
    required this.clave,
    required this.tags,
    this.descripcion = '',
    this.variables = const {},
  });

  /// El nombre corto: `pe`, `co`, `mx`. Es lo que se ve en la UI y lo que ata la
  /// cuenta con su etiqueta (`acct-pe`).
  final String clave;

  /// Las etiquetas de flow que corren con esta cuenta, **sin** el prefijo `acct-`.
  /// Para la cuenta peruana: `{pe, any}`.
  final Set<String> tags;

  /// Para qué sirve, en una línea. «PEN verificada, sin Bre-B».
  final String descripcion;

  /// Las credenciales y fixtures. `EMAIL`, `PASSWORD`, `PIN_1`…, `APP_ID`.
  ///
  /// 🔴 **Nunca se escriben en el clon del repo.** Nexus invoca `maestro test` con
  /// `-e CLAVE=valor` una por una —lo hace ya, y `LasVariablesDelProyecto` explica
  /// por qué es la única vía—, así que no hace falta generar ningún `config.yaml`
  /// dentro del árbol clonado. Es lo que hace imposible empujar una contraseña:
  /// no está en el sitio desde el que se empuja.
  final Map<String, String> variables;

  CuentaDePruebas copiaCon({
    String? clave,
    Set<String>? tags,
    String? descripcion,
    Map<String, String>? variables,
  }) => CuentaDePruebas(
    clave: clave ?? this.clave,
    tags: tags ?? this.tags,
    descripcion: descripcion ?? this.descripcion,
    variables: variables ?? this.variables,
  );

  /// Qué claves le faltan de las que el flow pide. Es lo que se le enseña a alguien
  /// cuando una pasada no puede arrancar: los **nombres**, nunca los valores.
  List<String> leFaltan(Iterable<String> pedidas) => [
    for (final clave in pedidas)
      if ((variables[clave] ?? '').isEmpty) clave,
  ];

  Map<String, Object?> aJson() => {
    'clave': clave,
    'tags': tags.toList()..sort(),
    'descripcion': descripcion,
    'variables': variables,
  };

  static CuentaDePruebas? deJson(Object? crudo) {
    if (crudo is! Map) return null;
    final clave = (crudo['clave'] as String?)?.trim() ?? '';
    if (clave.isEmpty) return null;

    final tags = <String>{
      for (final t in (crudo['tags'] as List?) ?? const [])
        if (t is String && t.trim().isNotEmpty) t.trim(),
    };

    final variables = <String, String>{};
    final vs = crudo['variables'];
    if (vs is Map) {
      vs.forEach((k, v) {
        if (k is String && v is String) variables[k] = v;
      });
    }

    return CuentaDePruebas(
      clave: clave,
      // Sin tags la cuenta no la elige nadie, pero se conserva: puede estar a
      // medio configurar y borrarla en silencio sería peor que dejarla inerte.
      tags: tags,
      descripcion: (crudo['descripcion'] as String?) ?? '',
      variables: variables,
    );
  }
}

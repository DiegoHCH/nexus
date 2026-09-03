/// Qué tan grave es una línea del registro del dispositivo.
///
/// Ordenado a propósito: el filtro es «de este nivel para arriba», y con un
/// `enum` suelto habría que mantener una tabla aparte para comparar.
enum NivelDeRegistro {
  verboso,
  depuracion,
  info,
  aviso,
  error,
  fatal;

  bool alMenos(NivelDeRegistro minimo) => index >= minimo.index;
}

/// Una línea del registro del sistema del dispositivo.
///
/// 🔴 **Esto no es lo que ya se ve.** `flutter run` reenvía lo que la app
/// imprime, y eso Nexus ya lo enseña. Lo que falta —y es la mitad de la
/// respuesta a «por qué se cayó»— es lo que dice el **sistema**: un crash
/// nativo, un ANR, el `Fatal signal 11`. Eso no pasa por el daemon de Flutter y
/// hoy obliga a salir a la terminal, que es justo lo que la app vino a evitar.
class LineaDeRegistro {
  const LineaDeRegistro({
    required this.nivel,
    required this.etiqueta,
    required this.texto,
    this.pid,
  });

  final NivelDeRegistro nivel;

  /// De quién viene: el `tag` en Android, el nombre del proceso en iOS.
  final String etiqueta;

  final String texto;

  /// El proceso que la escribió, cuando el formato lo trae. Es lo que permitiría
  /// quedarse solo con las de la app lanzada.
  final int? pid;

  @override
  bool operator ==(Object other) =>
      other is LineaDeRegistro &&
      other.nivel == nivel &&
      other.etiqueta == etiqueta &&
      other.texto == texto &&
      other.pid == pid;

  @override
  int get hashCode => Object.hash(nivel, etiqueta, texto, pid);

  @override
  String toString() => '${nivel.name}/$etiqueta: $texto';
}

import 'package:nexus/features/workspace/domain/entities/workspace.dart';

/// Si Claude puede escribir **en esta carpeta**, contando los tres que opinan.
///
/// 🔴 **El permiso era de la app y todo el mundo creía que era de la carpeta.**
/// El reporte que lo destapó empezó con «la carpeta ya tiene permiso de puede
/// editar», que es el modelo mental natural con tres conversaciones abiertas
/// sobre repos distintos — y con un solo interruptor global, dárselo a tu
/// proyecto se lo daba también al del trabajo.
///
/// Ahora opinan tres, y el orden no es negociable porque cada uno protege algo
/// distinto:
///
/// 1. **El tope de la app.** Es el cerrojo de arriba: en solo lectura no se
///    escribe en ninguna parte, y para eso existe.
/// 2. **La carpeta.** Es la decisión del día a día, la que se toca en el
///    compositor mientras se trabaja.
/// 3. **El repositorio.** Un `.nexus/config.json` puede declararse de solo
///    lectura y eso **gana** — pero solo hacia abajo: un repo no puede
///    concederse una escritura que nadie le dio. Es la misma regla que ya
///    seguían los comandos permitidos, y por el mismo motivo: ampliar permisos
///    es decisión de quien empareja la carpeta, nunca del contenido de la
///    carpeta.
///
/// Puro y aparte de las entidades porque es **la regla**, no el dato: así se
/// prueba sin construir un espacio de trabajo entero, y hay un solo sitio donde
/// leerla — que es lo que faltaba cuando la respuesta estaba repartida entre un
/// `enum`, un widget y un proveedor.
abstract final class ElPermisoQueVale {
  /// Con las tres piezas ya en la mano.
  static bool puedeEscribir({
    required FilePermission tope,
    required bool laCarpeta,
    required bool elRepoEsDeSoloLectura,
  }) => tope.canWrite && laCarpeta && !elRepoEsDeSoloLectura;

  /// Lo mismo, buscando las piezas en el espacio de trabajo.
  ///
  /// Sin carpeta —o con una que no está emparejada— **no se escribe**: es el
  /// caso de la carpeta de documentos y de cualquier ruta que llegue de fuera,
  /// y ahí la respuesta segura es no.
  static bool enLaCarpeta(Workspace workspace, String? path) {
    if (path == null) return false;
    final carpeta = workspace.folders
        .where((folder) => folder.path == path)
        .firstOrNull;
    if (carpeta == null) return false;
    return puedeEscribir(
      tope: workspace.permission,
      laCarpeta: carpeta.puedeEditar,
      elRepoEsDeSoloLectura: workspace.delRepo[path]?.soloLectura ?? false,
    );
  }

  /// Si el tope de la app deja escribir a alguien.
  ///
  /// Lo usa el compositor para decir **por qué** su interruptor no basta: con el
  /// tope cerrado, dar permiso a una carpeta no la hace escribir, y un control
  /// que no hace lo que dice es peor que un control que falta.
  static bool elTopeLoPermite(Workspace workspace) =>
      workspace.permission.canWrite;
}

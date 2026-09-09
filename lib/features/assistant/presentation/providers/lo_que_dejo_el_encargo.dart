import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Qué dejó tocado un encargo: **el repositorio y los documentos**.
///
/// 🔴 **Sale del controlador del asistente**, que tenía 2.458 líneas y seis
/// trabajos dentro. Este es uno de los seis y de los más autocontenidos: toma
/// una foto al empezar, otra al acabar y resta. No pinta nada ni toca el
/// estado — devuelve datos, y quien los cuelga del mensaje es la conversación.
///
/// Está junto y no repartido porque **las dos mitades son la misma idea**: lo
/// que interesa es lo que dejó *este* encargo, no todo lo que hay en la carpeta.
/// Y las dos se han roto por lo mismo, comparar fotos que no eran comparables:
///
/// - `stash create` **no ve lo que git no sigue**, así que sin apuntar aparte
///   los archivos sin trackear, cualquier archivo suelto de ayer contaba como
///   creado por este encargo;
/// - y las cuentas de los documentos se leían con `.value` sobre un proveedor
///   asíncrono, así que la foto de «antes» podía tomarse **sin cuentas** y la de
///   «después» **con ellas**.
///
/// Uno por conversación: las fotos son suyas y dos encargos a la vez en carpetas
/// distintas no pueden compartirlas.
class LoQueDejoElEncargo {
  LoQueDejoElEncargo(this._ref);

  final Ref _ref;

  /// 🔴 **Esto se desmonta con la conversación**, y lo dijo la suite: quince
  /// pruebas en rojo con «Cannot use the Ref of
  /// `Provider<LoQueDejoElEncargo>` after it has been disposed». Todo lo de aquí
  /// corre con `unawaited` al final
  /// de un encargo y lee proveedores **después de un `await`**: si la pestaña se
  /// cierra mientras tanto, leerlos lanza — y lanza desde dentro de un
  /// `unawaited`, donde no lo atrapa nadie.
  ///
  /// Es exactamente el guardia que el controlador ya tenía para lo mismo. Se
  /// viene con el código, porque el problema se viene con el código.
  bool get _vive => _ref.mounted;

  /// Dónde estaba el repositorio antes de este encargo.
  String? _repoBase;

  /// Los documentos que había **antes de este encargo**, o `null` si nadie ha
  /// tomado la marca todavía.
  ///
  /// 🔴 **`null` y no un conjunto vacío, y esa es la diferencia que importa.**
  /// Vacío significa «mirado, y no había ninguno»; `null` significa «no se ha
  /// mirado». Confundirlos es lo que colgó un documento viejo de una respuesta
  /// que no tenía nada que ver: sin marca, restar contra el vacío hace que
  /// **toda** la carpeta parezca recién salida.
  ///
  /// Con esto, un camino que llegue al final de un encargo sin haber tomado la
  /// marca no cuelga nada — que es lo correcto, porque no hay forma de saber
  /// qué es nuevo.
  Set<String>? _documentosAntes;

  /// Y qué archivos había ya sin trackear. La marca de git tiene dos mitades y
  /// esta faltaba: `stash create` no ve lo que git no sigue, así que sin esto
  /// cualquier archivo suelto de ayer contaba como creado por este encargo.
  Set<String> _sinTrackearAntes = const {};

  /// La foto de antes. [donde] es la carpeta donde va a trabajar el encargo, o
  /// `null` si no hay ninguna —y entonces no hay nada que comparar—.
  Future<void> tomaLaMarca(String? donde) async {
    if (donde == null) {
      _repoBase = null;
      _sinTrackearAntes = const {};
    } else {
      const git = GitDataSource();
      _repoBase = await git.snapshot(donde);
      _sinTrackearAntes = await git.sinTrackear(donde);
    }
    _documentosAntes = await _documentosAhora();
  }

  /// Qué tocó en el repositorio, o `null` si no se puede saber —sin carpeta o
  /// sin marca—.
  Future<GitChanges?> losCambios(String? donde) async {
    final base = _repoBase;
    if (donde == null || base == null) return null;
    return const GitDataSource().changesSince(
      donde,
      base,
      yaEstaban: _sinTrackearAntes,
    );
  }

  /// El documento que salió de este encargo, o `null`.
  ///
  /// **La marca se consume**: vale para un encargo, así que el siguiente tiene
  /// que tomar la suya. Dejarla puesta haría que un turno sin marca comparase
  /// contra la del anterior y colgase el documento de aquél.
  ///
  /// Se devuelve **el último** de los nuevos: si un encargo dejó tres, el que se
  /// enseña es el que acabó de escribir.
  Future<String?> elDocumentoNuevo() async {
    final antes = _documentosAntes;
    _documentosAntes = null;
    if (antes == null) return null;

    final nuevos = (await _documentosAhora()).difference(antes);
    if (nuevos.isEmpty || !_vive) return null;
    _ref.invalidate(artifactsProvider);
    return nuevos.last;
  }

  /// Las rutas de los documentos que hay ahora mismo en el cajón.
  Future<Set<String>> _documentosAhora() async {
    if (!_vive) return const {};
    final carpeta = _ref.read(artifactsFolderProvider);
    if (carpeta == null) return const {};
    // El data source se pide **antes** del `await` de las cuentas: después, la
    // conversación puede estar cerrada y pedirlo lanzaría.
    final cajon = _ref.read(artifactsDataSourceProvider);
    // 🔴 **Esperadas de verdad, no leídas a medias.** Aquí había un `.value`
    // sobre un proveedor asíncrono: mientras no ha resuelto vale `null`, así
    // que la foto de «antes» podía tomarse **sin cuentas** y la de «después»
    // **con ellas**. Comparar dos listas sacadas con reglas distintas convierte
    // la diferencia en basura: un documento guardado en la carpeta de una
    // cuenta aparece como nuevo sin serlo, o al revés. Y la ventana en la que
    // pasa no es teórica: el proveedor recorre el home al arrancar.
    final cuentas = await _ref
        .read(claudeProfilesProvider.future)
        .then((perfiles) => perfiles.map((perfil) => perfil.name).toSet())
        .catchError((Object _) => const <String>{});
    if (!_vive) return const {};
    final lista = await cajon.list(carpeta, cuentas: cuentas);
    return {for (final documento in lista) documento.path};
  }
}

/// Uno por conversación: las fotos son suyas.
final loQueDejoElEncargoProvider = Provider.family<LoQueDejoElEncargo, String>(
  (ref, conversationId) => LoQueDejoElEncargo(ref),
);

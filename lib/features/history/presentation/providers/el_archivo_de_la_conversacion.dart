import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';

/// Qué falló al guardar una conversación.
///
/// Los dos por separado, y no un booleano, porque **una cosa se arregla luego y
/// la otra no**: si el historial de la app la tiene, la conversación está a
/// salvo y lo que falta es una copia; si falló el local, se perdió.
@immutable
class LoQueFalloAlArchivar {
  const LoQueFalloAlArchivar({this.local = false, this.destino = false});

  /// El historial de la app, el que nunca depende de nada externo.
  final bool local;

  /// El destino que elegiste —una carpeta, el vault, Notion—.
  final bool destino;

  bool get algo => local || destino;
}

/// Quien **escribe** una conversación: el historial de la app y el destino que
/// se haya elegido.
///
/// 🔴 **Sale del controlador del asistente**, que tenía 2.458 líneas y seis
/// trabajos dentro: el ciclo del encargo y su cola, los permisos, la voz, el
/// parte del día, git y los documentos… y esto. No es una queja de estilo — era
/// donde aterrizaban todos los incidentes, y **la última carrera salió justo de
/// esa mezcla**: la cola daba paso al turno siguiente y el sellado del anterior
/// seguía por su cuenta, así que dos turnos escribían el mismo registro.
///
/// Con el archivado en su propio sitio, **es el único que escribe** y la fila
/// deja de ser algo que hay que acordarse de usar: es la única forma de entrar.
///
/// Uno por conversación —la familia va por su id— porque la fila es suya: dos
/// conversaciones escriben archivos distintos y serializarlas juntas sería
/// hacer esperar a una por la otra sin motivo.
class ElArchivoDeLaConversacion {
  ElArchivoDeLaConversacion(this._ref);

  final Ref _ref;

  /// Las escrituras van **en fila**.
  ///
  /// 🔴 Nació en el controlador, arreglando esto: `_afterErrand` da paso a la
  /// cola y **después** suelta el sellado, así que un turno encolado podía
  /// archivar mientras el anterior todavía buscaba su documento — y los dos
  /// escriben el mismo registro con los mensajes leídos en momentos distintos.
  /// Gana el último que serializa, y si es el de antes del sellado, el enlace
  /// del documento no queda en el disco.
  ///
  /// Es la misma medicina que ya toma el registro de la app —«las escrituras
  /// van en fila: dos a la vez sobre el mismo archivo pueden intercalarse a
  /// media línea»— un grado más arriba: aquí lo que se intercala son turnos.
  Future<void> _laFila = Future.value();

  /// Pone [tarea] al final de la fila.
  ///
  /// Un fallo **no rompe la fila**: lo que viene detrás es el turno siguiente, y
  /// quedarse sin fila es quedarse sin registro.
  Future<void> enFila(Future<void> Function() tarea) =>
      _laFila = _laFila.then((_) => tarea()).catchError((Object error) {
        debugPrint('archivo · la fila siguió tras un fallo: $error');
      });

  /// Guarda [registro] y cuenta qué falló.
  ///
  /// **Primero el historial de la app**, que no depende de nada externo: si
  /// dependiera del vault o de Notion, elegir «en ningún sitio» dejaría a Nexus
  /// sin memoria de lo que hiciste. Los dos fallos se recogen y se devuelven
  /// juntos, para que quien lo pidió los diga en un solo aviso — antes cada uno
  /// solo hacía `debugPrint`, y si el vault ya no existía la conversación se
  /// perdía **en silencio**: te enterabas el día que ibas a buscar la nota.
  ///
  /// [soloLocal] es la segunda pasada de un turno: no vuelve a salir de la
  /// máquina.
  Future<LoQueFalloAlArchivar> guardar(
    ConversationRecord registro, {
    bool soloLocal = false,
  }) async {
    // 🔴 **Los proveedores se piden antes de esperar.** Esto corre con
    // `unawaited` al final de un encargo y se desmonta con la conversación: si
    // la pestaña se cierra a mitad, leerlos después del `await` lanza «Cannot
    // use the Ref … after it has been disposed» — y lanza desde dentro de un
    // `unawaited`, donde no lo atrapa nadie. Lo dijo la suite en cuanto esto
    // salió del controlador, que ya tenía el mismo guardia.
    if (!_ref.mounted) return const LoQueFalloAlArchivar();
    final almacen = _ref.read(localConversationStoreProvider);
    final destinoFuturo = soloLocal
        ? null
        : _ref.read(conversationArchiveProvider.future);

    var falloLocal = false;
    try {
      await almacen.save(registro);
      // La lista de esa carpeta sí se refresca solo si sigue habiendo a quién
      // enseñársela.
      if (_ref.mounted) {
        _ref.invalidate(savedConversationsProvider(registro.folderPath));
      }
    } on Object catch (error) {
      falloLocal = true;
      debugPrint('archivo · no se pudo guardar en local: $error');
    }

    // **Resolver el destino también va dentro del `try`.** Estaba fuera, y eso
    // contradecía el párrafo de arriba: si averiguar cuál es el destino externo
    // fallaba —un vault que ya no está, una preferencia a medio escribir— esto
    // lanzaba desde dentro de un `unawaited` y quedaba como error sin atrapar.
    var falloElDestino = false;
    try {
      final destino = await destinoFuturo;
      if (destino != null) await destino.save(registro);
    } on Object catch (error) {
      // Que falle guardar no puede tumbar la conversación: la carpeta puede
      // haberse desconectado, o el vault puede no existir ya. Se dice y se
      // sigue — el historial de la app nunca depende del destino externo.
      falloElDestino = true;
      debugPrint('archivo · no se pudo archivar: $error');
    }

    return LoQueFalloAlArchivar(local: falloLocal, destino: falloElDestino);
  }
}

/// Uno por conversación: la fila es suya. Ver [ElArchivoDeLaConversacion].
final elArchivoDeLaConversacionProvider =
    Provider.family<ElArchivoDeLaConversacion, String>(
      (ref, conversationId) => ElArchivoDeLaConversacion(ref),
    );

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/domain/usecases/la_sesion_que_se_comparte.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';

/// Suelta la sesión de una carpeta cuando ya no queda **ni un registro** suyo.
///
/// 🔴 **Cerrar no olvida, y eso tiene un motivo bueno: el archivo.** Si cerrar
/// tirara la sesión, retomar una conversación archivada volvería sin memoria —
/// justo lo que fuiste a buscar al retomarla. Pero el efecto secundario era
/// éste: cierras todo, borras lo guardado, abres una conversación nueva sobre
/// esa carpeta… y el modelo sigue acordándose. **Y nada te lo dice.**
///
/// Así que la regla fina: mientras exista un registro —abierto o archivado— la
/// sesión sigue; cuando no queda ninguno, no hay nada que continuar y guardarla
/// es guardar un hilo sin dueño.
///
/// Se llama desde los dos sitios que pueden dejarla huérfana: cerrar una
/// conversación y borrar una del archivo. **Dos caminos hacia lo mismo pasan
/// por aquí**, que es la regla que salió de haberlo arreglado tres veces en un
/// sitio y no en el otro.
final laSesionSinDuenoProvider = Provider<Future<void> Function(String)>((ref) {
  return (folderPath) async {
    final quedanAbiertas = ref
        .read(conversationsProvider)
        .items
        .any((item) => item.folderPath == folderPath);

    var seLeyoElArchivo = true;
    var quedanArchivadas = false;
    try {
      final guardadas = await ref
          .read(localConversationStoreProvider)
          .list(folderPath);
      quedanArchivadas = guardadas.isNotEmpty;
    } on Object catch (error) {
      // **Un fallo de disco no es una lista vacía.** Tirar la sesión por no
      // haber podido mirar es el error que no se puede deshacer, así que se
      // anota y se deja como estaba. Es el mismo criterio con el que se cierran
      // las conversaciones vacías al arrancar.
      debugPrint('nexus.sesion · no se pudo leer el archivo: $error');
      seLeyoElArchivo = false;
    }

    if (!LaSesionQueSeComparte.seQuedoSinDueno(
      quedanAbiertas: quedanAbiertas,
      quedanArchivadas: quedanArchivadas,
      seLeyoElArchivo: seLeyoElArchivo,
    )) {
      return;
    }

    debugPrint('nexus.sesion · sin registros en $folderPath: se olvida');
    await ref.read(conversationMemoryProvider).forget(folderPath);
  };
});

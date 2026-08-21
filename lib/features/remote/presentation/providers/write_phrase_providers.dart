import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/storage/secure_storage_data_source.dart';
import 'package:nexus/features/remote/data/write_phrase_store_impl.dart';
import 'package:nexus/features/remote/domain/write_phrase.dart';

final writePhraseStoreProvider = Provider<WritePhraseStore>(
  (ref) => WritePhraseStoreImpl(SecureStorageDataSource()),
);

/// Quien concede y caduca el permiso de escritura.
///
/// Uno solo para todo el canal, y no uno por conexión: el permiso es del canal
/// —así lo fija la 2.4— y uno por conexión dejaría que reconectar reiniciara el
/// cupo de intentos, que es la forma más fácil de saltárselo.
final writeUnlockProvider = Provider<WriteUnlock>((ref) => WriteUnlock());

/// Si hay frase definida. **Nunca su valor** hacia la interfaz: lo que la pantalla
/// necesita saber es si existe, no cuál es.
class WritePhraseController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async =>
      await ref.read(writePhraseStoreProvider).read() != null;

  /// Guarda una nueva. Devuelve `false` si no llega al mínimo — sin guardarla.
  Future<bool> definir(String texto) async {
    final frase = WritePhrase(texto.trim());
    if (!frase.valida) return false;
    await ref.read(writePhraseStoreProvider).write(frase);
    // Cambiar la frase **cierra la ventana abierta**: si no, quien tuviera permiso
    // seguiría escribiendo con una frase que ya no existe — y cambiarla es lo que
    // hace alguien que quiere cortar el acceso.
    ref.read(writeUnlockProvider).revocar();
    state = const AsyncData(true);
    return true;
  }

  Future<void> borrar() async {
    await ref.read(writePhraseStoreProvider).clear();
    ref.read(writeUnlockProvider).revocar();
    state = const AsyncData(false);
  }
}

final writePhraseControllerProvider =
    AsyncNotifierProvider<WritePhraseController, bool>(
      WritePhraseController.new,
    );

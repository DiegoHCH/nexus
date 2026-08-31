import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/remote/presentation/providers/channel_token_providers.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus/features/remote/presentation/providers/write_phrase_providers.dart';

/// Los secretos que Nexus guarda en el llavero del Mac.
///
/// Están repartidos por tres features —la voz, el canal, el emparejamiento— y
/// hasta ahora no había ningún sitio donde verlos juntos: para saber qué tenías
/// guardado había que abrir Acceso a Llaveros y buscar por el nombre interno de
/// la clave. Esto es ese inventario.
///
/// 🔴 **El valor no sale de aquí, ni por asomo.** Lo único que se dice es si hay
/// una guardada o no. Enseñar aunque fuera una cola de cuatro caracteres pondría
/// un secreto en pantalla —y en cualquier captura, y en cualquier pantalla
/// compartida— a cambio de casi nada: para saber si es la que crees, la quitas y
/// pones la buena.
enum LlaveDeNexus {
  /// La de Gemini, que enciende la voz.
  voz,

  /// Con el que entra el teléfono al canal del escritorio.
  tokenDelCanal,

  /// La que hay que decir desde el móvil para poder escribir.
  fraseDeEscritura,

  /// El emparejamiento con el que quedó atado un teléfono.
  emparejamiento,
}

/// Cuáles hay puestas ahora mismo.
final lasLlavesGuardadasProvider = FutureProvider<Map<LlaveDeNexus, bool>>((
  ref,
) async {
  Future<bool> hay(Future<Object?> lectura) async => await lectura != null;

  return {
    LlaveDeNexus.voz: await hay(ref.watch(geminiKeyStoreProvider).read()),
    LlaveDeNexus.tokenDelCanal: await hay(
      ref.watch(channelTokenStoreProvider).read(),
    ),
    LlaveDeNexus.fraseDeEscritura: await hay(
      ref.watch(writePhraseStoreProvider).read(),
    ),
    LlaveDeNexus.emparejamiento: await hay(
      ref.watch(pairingStoreProvider).read(),
    ),
  };
});

/// Quita una, y **por el camino de su propia feature**.
///
/// 🔴 Borrar la entrada del llavero a mano sería más corto y estaría mal: el
/// token del canal y el emparejamiento viven además en memoria, en sus
/// controladores. Vaciando el llavero por detrás, la app seguiría creyendo que
/// hay token hasta el siguiente arranque — y el canal seguiría abierto con uno
/// que ya no existe en disco.
final olvidarUnaLlaveProvider = Provider<Future<void> Function(LlaveDeNexus)>((
  ref,
) {
  return (llave) async {
    switch (llave) {
      case LlaveDeNexus.voz:
        await ref.read(geminiKeyStoreProvider).clear();
        // Lo que decide si la voz se puede encender lee de aquí.
        ref.invalidate(geminiKeyStoreProvider);
      case LlaveDeNexus.tokenDelCanal:
        await ref.read(channelTokenControllerProvider.notifier).revocar();
      case LlaveDeNexus.fraseDeEscritura:
        await ref.read(writePhraseControllerProvider.notifier).borrar();
      case LlaveDeNexus.emparejamiento:
        await ref.read(pairingControllerProvider.notifier).olvidar();
    }
    ref.invalidate(lasLlavesGuardadasProvider);
  };
});

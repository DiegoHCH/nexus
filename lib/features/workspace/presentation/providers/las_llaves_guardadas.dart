import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/remote/presentation/providers/channel_token_providers.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus/features/remote/presentation/providers/write_phrase_providers.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Los secretos que Nexus guarda en el llavero del Mac.
///
/// Están repartidos por tres features —la voz, las imágenes, el canal— y hasta
/// que existió esto no había ningún sitio donde verlos juntos: para saber qué
/// tenías guardado había que abrir Acceso a Llaveros y buscar por el nombre
/// interno de la clave.
///
/// 🔴 **El valor no sale de aquí, ni por asomo.** Lo único que se dice es si hay
/// una guardada. Enseñar aunque fuera una cola de cuatro caracteres pondría un
/// secreto en pantalla —y en cualquier captura, y en cualquier pantalla
/// compartida— a cambio de casi nada: para saber si es la que crees, la quitas
/// y pones la buena.
enum LlaveDeNexus {
  /// La de Gemini, que enciende la voz.
  voz,

  /// La otra de Gemini: con la que se generan imágenes. **Hay una por cuenta**
  /// de Claude, porque el gasto sale de un bolsillo concreto.
  imagenes,

  /// Con el que entra el teléfono al canal del escritorio.
  tokenDelCanal,

  /// La que hay que decir desde el móvil para poder escribir.
  fraseDeEscritura,

  /// El emparejamiento con el que quedó atado un teléfono.
  emparejamiento,
}

/// Una fila del llavero, ya resuelta.
@immutable
class LlaveEnElLlavero {
  const LlaveEnElLlavero({required this.cual, required this.hay, this.perfil});

  final LlaveDeNexus cual;
  final bool hay;

  /// De qué cuenta de Claude es. Solo lo llevan las de imágenes; `null` es la
  /// cuenta de siempre, la que no tiene nombre.
  final String? perfil;

  @override
  bool operator ==(Object other) =>
      other is LlaveEnElLlavero &&
      other.cual == cual &&
      other.hay == hay &&
      other.perfil == perfil;

  @override
  int get hashCode => Object.hash(cual, hay, perfil);
}

/// Las cuentas para las que puede haber una llave de imágenes: la de siempre y
/// cada `.claude-*` que haya en el Mac.
///
/// La de siempre va primero y **no la lista** `claudeProfilesProvider`, que solo
/// devuelve las que tienen nombre — para él, la de siempre es la ausencia de
/// perfil. Aquí sí tiene que aparecer: se le puede poner llave igual.
List<String?> cuentasParaLlaves(List<ClaudeProfile> perfiles) => [
  null,
  ...perfiles.map((p) => ClaudeProfile.nameFromPath(p.path)).nonNulls,
];

/// Cuáles hay puestas ahora mismo.
final lasLlavesGuardadasProvider = FutureProvider<List<LlaveEnElLlavero>>((
  ref,
) async {
  Future<bool> hay(Future<Object?> lectura) async => await lectura != null;

  final imagenes = ref.watch(geminiImageKeyStoreProvider);
  // `await …future` y no `.value`: dentro de un `FutureProvider` hay que
  // esperar de verdad. Con `.value` se leía `null` mientras cargaba, se
  // devolvía la lista sin cuentas y el proveedor se quedaba a medias.
  final cuentas = cuentasParaLlaves(
    await ref.watch(claudeProfilesProvider.future),
  );

  return [
    LlaveEnElLlavero(
      cual: LlaveDeNexus.voz,
      hay: await hay(ref.watch(geminiKeyStoreProvider).read()),
    ),
    for (final cuenta in cuentas)
      LlaveEnElLlavero(
        cual: LlaveDeNexus.imagenes,
        perfil: cuenta,
        hay: await hay(imagenes.read(cuenta)),
      ),
    LlaveEnElLlavero(
      cual: LlaveDeNexus.tokenDelCanal,
      hay: await hay(ref.watch(channelTokenStoreProvider).read()),
    ),
    LlaveEnElLlavero(
      cual: LlaveDeNexus.fraseDeEscritura,
      hay: await hay(ref.watch(writePhraseStoreProvider).read()),
    ),
    LlaveEnElLlavero(
      cual: LlaveDeNexus.emparejamiento,
      hay: await hay(ref.watch(pairingStoreProvider).read()),
    ),
  ];
});

/// Quita una, y **por el camino de su propia feature**.
///
/// 🔴 Borrar la entrada del llavero a mano sería más corto y estaría mal: el
/// token del canal y el emparejamiento viven además en memoria, en sus
/// controladores. Vaciando el llavero por detrás, la app seguiría creyendo que
/// hay token hasta el siguiente arranque — y el canal seguiría abierto con uno
/// que ya no existe en disco.
final olvidarUnaLlaveProvider =
    Provider<Future<void> Function(LlaveEnElLlavero)>((ref) {
      return (llave) async {
        switch (llave.cual) {
          case LlaveDeNexus.voz:
            await ref.read(geminiKeyStoreProvider).clear();
            // Lo que decide si la voz se puede encender lee de aquí.
            ref.invalidate(geminiKeyStoreProvider);
          case LlaveDeNexus.imagenes:
            await ref.read(geminiImageKeyStoreProvider).clear(llave.perfil);
            ref.invalidate(hayLlaveDeImagenesProvider(llave.perfil));
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

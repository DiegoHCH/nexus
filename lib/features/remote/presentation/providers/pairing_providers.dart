import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/storage/secure_storage_data_source.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/data/pairing_store_impl.dart';
import 'package:nexus/features/remote/domain/pairing.dart';

/// Lo que el teléfono sabe del Mac.
final pairingStoreProvider = Provider<PairingStore>(
  (ref) => PairingStoreImpl(SecureStorageDataSource()),
);

/// La versión de la app que se anuncia en el saludo. Se sobrescribe al arrancar con
/// la de verdad; el valor de aquí solo sirve en pruebas.
final appVersionProvider = Provider<String>((ref) => '0.0.0');

/// El emparejamiento guardado. `null` es «sin emparejar», que es como nace.
class PairingController extends AsyncNotifier<Pairing?> {
  @override
  Future<Pairing?> build() => ref.read(pairingStoreProvider).read();

  /// Guarda lo que se pegó. Devuelve el problema, o `null` si quedó emparejado.
  Future<PairingProblem?> emparejar({
    required String url,
    required String token,
  }) async {
    final leido = leerEmparejamiento(url: url, token: token);
    if (leido.problema != null) return leido.problema;

    await ref.read(pairingStoreProvider).write(leido.emparejamiento!);
    state = AsyncData(leido.emparejamiento);
    return null;
  }

  /// Olvida el Mac. **Y corta el enlace**: dejar la conexión viva después de
  /// desemparejar sería seguir hablando con un sitio del que ya se dijo que no.
  Future<void> olvidar() async {
    await ref.read(channelLinkProvider).desconectar();
    await ref.read(pairingStoreProvider).clear();
    state = const AsyncData(null);
  }
}

final pairingControllerProvider =
    AsyncNotifierProvider<PairingController, Pairing?>(PairingController.new);

/// Cómo se abre el socket. Aparte para poder probar el arranque **sin red**.
final socketOpenerProvider = Provider<Future<ChannelSocket> Function(Pairing)>(
  (ref) =>
      (pareja) => WebSocketChannelSocket.conectar(
        url: pareja.url,
        token: pareja.token.value,
      ),
);

/// El enlace, uno para toda la app.
///
/// Se construye una vez y **no por pantalla**: si cada pantalla abriera el suyo,
/// navegar reconectaría — y con eso el `seq` de los eventos volvería a empezar,
/// que es pedir un resync por cada toque.
final channelLinkProvider = Provider<ChannelLink>((ref) {
  final abrir = ref.read(socketOpenerProvider);
  final enlace = ChannelLink(
    abrir: () async {
      final pareja = ref.read(pairingControllerProvider).value;
      if (pareja == null) throw StateError('sin emparejar');
      return abrir(pareja);
    },
    appVersion: ref.read(appVersionProvider),
  );
  ref.onDispose(() => unawaited(enlace.cerrar()));
  return enlace;
});

/// En qué anda la conexión, para la pantalla.
///
/// Es la decisión `lo6` cumplida: **el estado se dice**, no se deduce del silencio.
/// En esta app pesa más que en otras porque un encargo dura minutos y el orbe usa el
/// silencio como estado normal — sin señal explícita, «está pensando» y «no llego al
/// Mac» se dibujan idénticos.
final linkStateProvider = StreamProvider<LinkState>((ref) {
  final enlace = ref.watch(channelLinkProvider);
  // Con el valor de ahora delante: un `Stream` empieza vacío, y la pantalla
  // arrancaría sin saber nada durante un fotograma.
  return enlace.estado.transform(
    StreamTransformer.fromBind((fuente) async* {
      yield enlace.ahora;
      yield* fuente;
    }),
  );
});

/// Conecta cuando hay con quién, y no antes.
///
/// Vive en un provider y no en el `initState` de una pantalla porque conectar no es
/// de una pantalla: sobrevive a navegar, y morir al salir de la primera vista sería
/// desconectar al mirar la lista de conversaciones.
final autoConnectProvider = Provider<void>((ref) {
  final pareja = ref.watch(pairingControllerProvider).value;
  if (pareja == null) return;
  unawaited(ref.read(channelLinkProvider).conectar());
});

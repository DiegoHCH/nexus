import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/storage/secure_storage_data_source.dart';
import 'package:nexus/features/remote/data/channel_token_store_impl.dart';
import 'package:nexus/features/remote/domain/channel_token.dart';

final channelTokenStoreProvider = Provider<ChannelTokenStore>(
  (ref) => ChannelTokenStoreImpl(SecureStorageDataSource()),
);

/// El token del canal: el que hay, o ninguno.
///
/// `null` es un estado legítimo y es el del primer arranque — no un error. Quien
/// lo lea tiene que distinguirlo de «no se pudo leer el llavero», que también
/// devuelve `null` por la deuda b5: sin llavero legible hay que volver a generar,
/// que es reparable, y colgar el arranque no lo es.
class ChannelTokenController extends AsyncNotifier<ChannelToken?> {
  @override
  Future<ChannelToken?> build() => ref.read(channelTokenStoreProvider).read();

  /// Genera uno si no hay. **No lo rota si ya existe**: llamar a esto al arrancar
  /// el servidor no puede invalidar el teléfono que ya estaba emparejado.
  Future<ChannelToken> asegurar() async {
    final store = ref.read(channelTokenStoreProvider);
    final actual = await store.read();
    if (actual != null) return actual;
    final nuevo = ChannelToken.generar();
    await store.write(nuevo);
    state = AsyncData(nuevo);
    return nuevo;
  }

  /// Uno nuevo, y **todos los teléfonos fuera**.
  ///
  /// Es la decisión 2.1 del contrato: rotar es la forma de revocar. No hay lista de
  /// dispositivos que quitar uno a uno, y no la hay a propósito — con un token
  /// compartido, «expulsar a uno» sería mentira.
  Future<ChannelToken> rotar() async {
    final nuevo = ChannelToken.generar();
    await ref.read(channelTokenStoreProvider).write(nuevo);
    state = AsyncData(nuevo);
    return nuevo;
  }

  /// Deja el canal sin token: nadie entra hasta que se genere otro.
  Future<void> revocar() async {
    await ref.read(channelTokenStoreProvider).clear();
    state = const AsyncData(null);
  }
}

final channelTokenControllerProvider =
    AsyncNotifierProvider<ChannelTokenController, ChannelToken?>(
      ChannelTokenController.new,
    );

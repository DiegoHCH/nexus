import 'package:nexus/core/storage/secure_storage_data_source.dart';
import 'package:nexus/features/remote/domain/channel_token.dart';

/// El token del canal, en el llavero del Mac.
///
/// En el mismo sitio que la llave de Gemini y por el mismo camino: el llavero del
/// login, cifrado y protegido por la contraseña de la cuenta. Un secreto que abre
/// el acceso a `claude -p` con permiso de escritura no puede estar en
/// `SharedPreferences`, que es un archivo de texto en el disco.
class ChannelTokenStoreImpl implements ChannelTokenStore {
  const ChannelTokenStoreImpl(this._storage);

  static const _key = 'remote_channel_token';

  final SecureStorageDataSource _storage;

  @override
  Future<ChannelToken?> read() async {
    final guardado = await _storage.read(_key);
    // Vacío cuenta como no haber: una cadena vacía guardada por accidente sería un
    // token que el portero compararía —y con el que nadie entraría, pero que haría
    // creer que el canal está configurado.
    if (guardado == null || guardado.isEmpty) return null;
    return ChannelToken(guardado);
  }

  @override
  Future<void> write(ChannelToken token) => _storage.write(_key, token.value);

  @override
  Future<void> clear() => _storage.delete(_key);
}

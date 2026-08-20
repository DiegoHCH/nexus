import 'package:nexus/core/storage/secure_storage_data_source.dart';
import 'package:nexus/features/remote/domain/write_phrase.dart';

/// La frase de escritura, en el llavero del Mac.
///
/// En el mismo sitio que el token y que la llave de Gemini. Y **solo aquí**: el
/// teléfono no la guarda nunca, que es lo que hace que llevarse el teléfono no
/// baste para escribir.
class WritePhraseStoreImpl implements WritePhraseStore {
  const WritePhraseStoreImpl(this._storage);

  static const _key = 'remote_write_phrase';

  final SecureStorageDataSource _storage;

  @override
  Future<WritePhrase?> read() async {
    final guardada = await _storage.read(_key);
    // Vacía cuenta como no haber. Sin esto, una cadena vacía guardada por accidente
    // sería una frase que **cualquier intento vacío acertaría**.
    if (guardada == null || guardada.isEmpty) return null;
    return WritePhrase(guardada);
  }

  @override
  Future<void> write(WritePhrase phrase) => _storage.write(_key, phrase.value);

  @override
  Future<void> clear() => _storage.delete(_key);
}

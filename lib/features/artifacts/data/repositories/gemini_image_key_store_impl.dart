import 'package:nexus/core/storage/secure_storage_data_source.dart';
import 'package:nexus/features/artifacts/domain/repositories/gemini_image_key_store.dart';

class GeminiImageKeyStoreImpl implements GeminiImageKeyStore {
  const GeminiImageKeyStoreImpl(this._storage);

  /// Otra entrada del llavero, no la misma con otro nombre: quitar la de
  /// imágenes no puede dejarte sin voz.
  static const _key = 'gemini_image_api_key';

  final SecureStorageDataSource _storage;

  @override
  Future<String?> read() => _storage.read(_key);

  @override
  Future<void> save(String key) => _storage.write(_key, key);

  @override
  Future<void> clear() => _storage.delete(_key);
}

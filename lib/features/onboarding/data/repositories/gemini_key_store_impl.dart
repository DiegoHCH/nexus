import 'package:nexus/core/storage/secure_storage_data_source.dart';
import 'package:nexus/features/onboarding/domain/repositories/gemini_key_store.dart';

class GeminiKeyStoreImpl implements GeminiKeyStore {
  const GeminiKeyStoreImpl(this._storage);

  static const _key = 'gemini_api_key';

  final SecureStorageDataSource _storage;

  @override
  Future<String?> read() => _storage.read(_key);

  @override
  Future<void> save(String key) => _storage.write(_key, key);

  @override
  Future<void> clear() => _storage.delete(_key);
}

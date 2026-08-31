import 'package:nexus/core/storage/secure_storage_data_source.dart';
import 'package:nexus/features/artifacts/domain/repositories/gemini_image_key_store.dart';

class GeminiImageKeyStoreImpl implements GeminiImageKeyStore {
  const GeminiImageKeyStoreImpl(this._storage);

  /// Otra entrada del llavero, no la misma con otro nombre: quitar la de
  /// imágenes no puede dejarte sin voz.
  static const _base = 'gemini_image_api_key';

  /// La cuenta va en el sufijo, y **la de siempre se queda sin él**: así una
  /// llave guardada antes de que esto existiera sigue siendo la de la cuenta
  /// por defecto en vez de quedarse huérfana.
  static String claveDe(String? perfil) =>
      perfil == null || perfil.isEmpty ? _base : '$_base.$perfil';

  final SecureStorageDataSource _storage;

  @override
  Future<String?> read(String? perfil) => _storage.read(claveDe(perfil));

  @override
  Future<void> save(String? perfil, String key) =>
      _storage.write(claveDe(perfil), key);

  @override
  Future<void> clear(String? perfil) => _storage.delete(claveDe(perfil));
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Envuelve el almacén cifrado del sistema (Keychain en macOS). Lo único que
/// le importa a la app es leer/escribir un valor por clave; el resto de
/// opciones del paquete (accesibilidad de iOS, backend de Linux) no aplican
/// aquí.
class SecureStorageDataSource {
  SecureStorageDataSource({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
}

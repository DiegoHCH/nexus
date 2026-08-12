import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Envuelve el almacén cifrado del sistema (Keychain en macOS). Lo único que
/// le importa a la app es leer/escribir un valor por clave; el resto de
/// opciones del paquete (accesibilidad de iOS, backend de Linux) no aplican
/// aquí.
class SecureStorageDataSource {
  SecureStorageDataSource({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(mOptions: _macOptions);

  /// Keychain clásico (el del login) en vez del *data protection keychain*.
  ///
  /// El de protección de datos exige el entitlement `keychain-access-groups`,
  /// y ese —con perfil o sin él, con grupo explícito o con el array vacío—
  /// obliga a un *provisioning profile*, que a su vez exige tener este Mac
  /// registrado en la cuenta de desarrollador. La app ya se firma con
  /// certificado real (Developer ID, equipo Y9H7TRB5L7), así que lo único que
  /// falta para dar el salto es ese registro. El keychain del login está
  /// cifrado igual y protegido por la contraseña de la cuenta, así que la
  /// promesa de la pantalla ("se guarda cifrada en este Mac") se mantiene.
  static const _macOptions = MacOsOptions(usesDataProtectionKeychain: false);

  final FlutterSecureStorage _storage;

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

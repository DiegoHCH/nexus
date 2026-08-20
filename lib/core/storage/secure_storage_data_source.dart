import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// Devuelve `null` también cuando el llavero **no se deja leer**, no solo
  /// cuando no hay nada guardado.
  ///
  /// Es el caso que la deuda b5 dejó anotado: la llave vive en el llavero del
  /// login, así que el día que se cambie de llavero —o que el sistema niegue
  /// el acceso— esta lectura falla. Dejar subir la excepción tenía una
  /// consecuencia peor que perder la llave: el arranque se quedaba esperando
  /// una respuesta que no llegaba nunca y la app se quedaba en el splash, con
  /// el orbe girando y sin decir nada. Sin llave legible hay que volver a
  /// pedirla, que es reparable; colgarse no.
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException catch (error) {
      debugPrint('No se pudo leer «$key» del llavero: ${error.message}');
      return null;
    }
  }

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  /// Borra una entrada. Se traga el fallo del llavero por lo mismo que [read]:
  /// **quien pide borrar un secreto no puede quedarse esperando.**
  ///
  /// Y el silencio aquí es menos grave que en la lectura: si el borrado falla, el
  /// token viejo sigue valiendo — pero quien rotó ya tiene uno nuevo guardado, así
  /// que el peor caso es una entrada huérfana, no un canal abierto.
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException catch (error) {
      debugPrint('No se pudo borrar «$key» del llavero: ${error.message}');
    }
  }
}

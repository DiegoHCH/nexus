import 'package:nexus/core/storage/secure_storage_data_source.dart';
import 'package:nexus/features/remote/domain/channel_token.dart';
import 'package:nexus/features/remote/domain/pairing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El emparejamiento, guardado **partido a propósito**.
///
/// El token va al almacén seguro —Keystore en Android, llavero en iOS— porque es el
/// secreto que abre el canal, y es lo que pide la decisión 2.1: quien se lleve el
/// teléfono no se lleva un archivo de texto con la llave dentro.
///
/// La dirección va a las preferencias normales, y no por descuido: **no es un
/// secreto**, y meterla en el almacén seguro costaría una llamada al canal nativo
/// para leer algo que no lo necesita — con el efecto raro de que un fallo del
/// llavero dejaría al teléfono sin saber ni a dónde iba.
class PairingStoreImpl implements PairingStore {
  const PairingStoreImpl(this._seguro);

  static const _claveToken = 'channel_pairing_token';
  static const _claveUrl = 'channel_pairing_url';

  final SecureStorageDataSource _seguro;

  @override
  Future<Pairing?> read() async {
    final token = await _seguro.read(_claveToken);
    if (token == null || token.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_claveUrl);
    if (url == null || url.isEmpty) return null;

    final leida = Uri.tryParse(url);
    // Media pareja no sirve de nada. Si una de las dos partes se perdió —se
    // desinstaló, se limpiaron las preferencias— es mejor volver a la pantalla de
    // emparejar que intentar conectar a un sitio a medias y contar «no responde».
    if (leida == null) return null;

    return Pairing(url: leida, token: ChannelToken(token));
  }

  @override
  Future<void> write(Pairing pairing) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveUrl, pairing.url.toString());
    // El token **al final**: si el llavero falla, no queda una dirección apuntando
    // a un emparejamiento que no existe.
    await _seguro.write(_claveToken, pairing.token.value);
  }

  @override
  Future<void> clear() async {
    // Y aquí al revés: primero el secreto. Si algo falla en medio, lo que sobrevive
    // es la parte que no abre nada.
    await _seguro.delete(_claveToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_claveUrl);
  }
}

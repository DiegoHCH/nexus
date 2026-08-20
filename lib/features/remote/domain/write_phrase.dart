import 'package:flutter/foundation.dart';
import 'package:nexus/features/remote/domain/constant_time.dart';

/// La frase que deja al teléfono escribir.
///
/// Es el segundo secreto del canal, y existe porque el token no puede ser el
/// único: quien se lleve el teléfono se lleva el token. La frase **no se guarda
/// nunca en el teléfono** — se teclea cuando hace falta y la verifica el Mac.
///
/// Y es lo que hace posible editar en remoto. La decisión 2.4 del contrato pedía
/// confirmar en el escritorio, y eso volvía imposible el caso principal: estando
/// fuera no hay nadie en el Mac. La frase cumple el requisito de verdad —exigir
/// algo que quien robe el teléfono no tenga— sin exigir además tu presencia.
@immutable
class WritePhrase {
  const WritePhrase(this.value);

  /// El mínimo, y no es decoración.
  ///
  /// Con el límite de intentos, adivinar por fuerza bruta está acotado — pero una
  /// frase de tres caracteres se adivina **dentro** del límite en unos días. Ocho
  /// es lo que convierte «acotado» en «inalcanzable».
  static const minimo = 8;

  final String value;

  bool get valida => value.trim().length >= minimo;

  /// Igual que el token: se enseña la huella y **nunca el valor**.
  ///
  /// Aquí importa más todavía, porque esta viaja **dentro de un mensaje** y no en
  /// una cabecera. El servidor registra el tipo de cada mensaje que llega, y una
  /// interpolación descuidada la dejaría escrita en el registro del sistema.
  @override
  String toString() => 'WritePhrase(${value.isEmpty ? "vacía" : "definida"})';

  @override
  bool operator ==(Object other) =>
      other is WritePhrase && igualesSinDelatar(other.value, value);

  /// **A propósito constante.**
  ///
  /// Un `hashCode` derivado del valor filtraría información del secreto a
  /// cualquier cosa que meta frases en un `Set` o en un `Map` — y el coste de
  /// devolver una constante es que esas colecciones degeneran en una lista, que
  /// para un único secreto no es coste ninguno.
  @override
  int get hashCode => 0;
}

/// Donde vive la frase entre arranques. Solo en el Mac.
abstract class WritePhraseStore {
  Future<WritePhrase?> read();
  Future<void> write(WritePhrase phrase);
  Future<void> clear();
}

/// El permiso de escritura concedido, con su caducidad.
///
/// **No se persiste, y eso es la mitad de su valor**: reiniciar la app deja el
/// canal en solo lectura otra vez. Un permiso que sobrevive a un reinicio es un
/// permiso que se queda abierto, que es justo lo que la caducidad viene a evitar.
@immutable
class WriteGrant {
  const WriteGrant({required this.until});

  /// Cuánto dura. Treinta minutos, y **no se renuevan con la actividad**: si se
  /// renovaran, un teléfono en uso lo mantendría abierto indefinidamente.
  static const duracion = Duration(minutes: 30);

  final DateTime until;

  bool vigenteEn(DateTime ahora) => ahora.isBefore(until);
}

/// Por qué no se concede.
enum WriteDenial {
  /// No hay frase definida en este Mac. El móvil se queda en solo lectura para
  /// siempre, y es el estado correcto por defecto: quien no la ha puesto no ha
  /// dicho en ningún momento que quiera que el teléfono escriba.
  sinFrase,

  /// La frase no era.
  frase,

  /// Demasiados intentos. Es un límite **propio**, aparte del de la conexión:
  /// adivinarla por un canal ya autenticado no puede ser gratis.
  demasiadosIntentos,
}

/// Verifica la frase y concede la ventana.
class WriteUnlock {
  WriteUnlock({
    this.intentos = 5,
    this.ventana = const Duration(minutes: 10),
    DateTime Function()? reloj,
  }) : _reloj = reloj ?? DateTime.now;

  /// Cinco por ventana. Con ocho caracteres de mínimo, cinco intentos cada diez
  /// minutos deja la fuerza bruta en el terreno de los siglos.
  final int intentos;
  final Duration ventana;
  final DateTime Function() _reloj;

  final _fallos = <DateTime>[];
  WriteGrant? _concedido;

  /// El permiso vigente, o `null`. Consultarlo **caduca lo que tenga que caducar**,
  /// así que no hace falta un temporizador que alguien pueda olvidarse de cancelar.
  WriteGrant? get grant {
    final actual = _concedido;
    if (actual == null) return null;
    if (!actual.vigenteEn(_reloj())) {
      _concedido = null;
      return null;
    }
    return actual;
  }

  bool get puedeEscribir => grant != null;

  /// Intenta abrir. `null` es que se concedió.
  WriteDenial? intentar({
    required WritePhrase? guardada,
    required String recibida,
  }) {
    _limpiarFallos();
    if (_fallos.length >= intentos) return WriteDenial.demasiadosIntentos;
    if (guardada == null) {
      // **No cuenta como fallo.** Sin frase definida, cualquier intento va a
      // fallar siempre, y gastarle el cupo a quien no puede acertar solo consigue
      // que el mensaje útil —«define una frase»— deje de llegar.
      return WriteDenial.sinFrase;
    }
    if (!igualesSinDelatar(guardada.value, recibida)) {
      _fallos.add(_reloj());
      return WriteDenial.frase;
    }
    _concedido = WriteGrant(until: _reloj().add(WriteGrant.duracion));
    // Un acierto limpia los fallos: quien se equivocó al teclear y luego acertó no
    // debería arrastrar el cupo gastado.
    _fallos.clear();
    return null;
  }

  /// Cierra la ventana ya. Lo usa rotar el token y lo usará el botón de echar a
  /// alguien: revocar el acceso y dejarle el permiso de escritura sería revocar a
  /// medias.
  void revocar() => _concedido = null;

  void _limpiarFallos() {
    final ahora = _reloj();
    _fallos.removeWhere((t) => ahora.difference(t) > ventana);
  }

  @visibleForTesting
  int get fallos {
    _limpiarFallos();
    return _fallos.length;
  }
}

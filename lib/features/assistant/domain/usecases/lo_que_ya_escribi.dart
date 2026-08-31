import 'package:flutter/foundation.dart';

/// El historial de la caja de texto, como el de una terminal.
///
/// Existe porque lo que uno escribe en un chat de trabajo **se repite**: el mismo
/// `!git status`, el mismo encargo con una palabra cambiada, la pregunta de ayer.
/// Volver a escribirlo entero es trabajo que la terminal resolvió hace cuarenta
/// años con una flecha.
///
/// ## De dónde sale
///
/// De los mensajes que ya enviaste en esta conversación, no de un almacén nuevo.
/// Son exactamente lo mismo —lo que escribiste, en orden— y un segundo sitio que
/// guardara lo mismo tendría que mantenerse sincronizado con el primero para
/// siempre.
@immutable
class LoQueYaEscribi {
  const LoQueYaEscribi({
    this.entradas = const [],
    this.posicion,
    this.borrador = '',
  });

  /// Lo enviado, **de lo más reciente a lo más viejo**. Es el orden en que se
  /// recorre, así que se guarda ya puesto en vez de invertirlo en cada flecha.
  final List<String> entradas;

  /// Dónde está el recorrido, o `null` si no se está recorriendo nada.
  ///
  /// La distinción no es cosmética: `null` significa «lo que hay en la caja es
  /// tuyo, recién escrito», y cualquier otro valor significa «lo que hay en la
  /// caja es una copia del historial». De eso depende que [borrador] se guarde
  /// una vez y no en cada pulsación.
  final int? posicion;

  /// Lo que estabas escribiendo cuando empezaste a mirar atrás.
  ///
  /// 🔴 **Se guarda porque perderlo es el error que más molesta.** Escribes
  /// media frase, subes a buscar algo parecido, cambias de idea y bajas — y la
  /// media frase tiene que seguir ahí. Sin esto, una flecha por curiosidad se
  /// come lo que llevabas escrito, y eso enseña a no usar la flecha.
  final String borrador;

  bool get recorriendo => posicion != null;

  /// Lo que debe aparecer en la caja: la entrada del recorrido, o tu borrador.
  String get texto {
    final donde = posicion;
    if (donde == null || donde < 0 || donde >= entradas.length) return borrador;
    return entradas[donde];
  }

  /// Prepara el historial a partir de lo enviado, en el orden en que llegó.
  ///
  /// **Se quitan los vacíos y los repetidos seguidos.** Los seguidos y no todos:
  /// haber escrito `!git status` tres veces en la mañana no debería costar tres
  /// flechas para pasar de largo, pero dos veces la misma cosa separadas por
  /// otras diez sí son dos momentos distintos y merecen su sitio — igual que
  /// `HISTCONTROL=ignoredups` y no `ignoreboth`.
  static LoQueYaEscribi de(Iterable<String> loEnviado, {String borrador = ''}) {
    final limpias = <String>[];
    for (final cruda in loEnviado) {
      final entrada = cruda.trim();
      if (entrada.isEmpty) continue;
      if (limpias.isNotEmpty && limpias.last == entrada) continue;
      limpias.add(entrada);
    }
    return LoQueYaEscribi(
      entradas: limpias.reversed.toList(),
      borrador: borrador,
    );
  }

  /// Un paso hacia atrás. [loQueHayAhora] es el contenido de la caja, que se
  /// guarda como borrador **solo al empezar** el recorrido.
  ///
  /// Al final del historial se queda quieto en vez de dar la vuelta: envolver
  /// haría que la flecha de más te devuelva lo que acabas de escribir, y eso se
  /// lee como un fallo.
  LoQueYaEscribi haciaAtras(String loQueHayAhora) {
    if (entradas.isEmpty) return this;
    if (!recorriendo) {
      return LoQueYaEscribi(
        entradas: entradas,
        posicion: 0,
        borrador: loQueHayAhora,
      );
    }
    final siguiente = posicion! + 1;
    if (siguiente >= entradas.length) return this;
    return LoQueYaEscribi(
      entradas: entradas,
      posicion: siguiente,
      borrador: borrador,
    );
  }

  /// Un paso hacia delante. Pasado el más reciente se sale del recorrido y
  /// vuelve tu borrador, que es lo que hace seguro haber subido.
  LoQueYaEscribi haciaAdelante() {
    if (!recorriendo) return this;
    final anterior = posicion! - 1;
    if (anterior < 0) {
      return LoQueYaEscribi(entradas: entradas, borrador: borrador);
    }
    return LoQueYaEscribi(
      entradas: entradas,
      posicion: anterior,
      borrador: borrador,
    );
  }

  /// Se sale del recorrido y se olvida el borrador: lo que se envió ya no está
  /// a medias, y lo que se escriba ahora empieza de cero.
  LoQueYaEscribi suelta() => LoQueYaEscribi(entradas: entradas);

  /// Si la flecha debe navegar el historial o mover el cursor.
  ///
  /// 🔴 **La caja tiene hasta seis líneas**, así que arriba también sirve para
  /// subir dentro de lo que estás escribiendo. Secuestrarla siempre rompería
  /// escribir un mensaje de varias líneas, que es lo que uno hace justo cuando
  /// más le importa el mensaje.
  ///
  /// La regla es la de las shells: se navega desde la **primera** línea y se
  /// vuelve desde la **última**. Se miran las líneas lógicas y no las que dibuja
  /// el ajuste de texto — una línea larga que se parte en tres cuenta como una,
  /// igual que en una terminal.
  static bool navegaHaciaAtras(String texto, int cursor) =>
      !texto.substring(0, cursor.clamp(0, texto.length)).contains('\n');

  static bool navegaHaciaAdelante(String texto, int cursor) =>
      !texto.substring(cursor.clamp(0, texto.length)).contains('\n');
}

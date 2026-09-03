import 'package:nexus/features/assistant/domain/repositories/microphone_access.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';

/// Si se puede abrir la sesión de voz, y si no, por qué no.
sealed class LaPuertaDeLaVoz {
  const LaPuertaDeLaVoz();
}

/// Adelante.
final class SePuedeHablar extends LaPuertaDeLaVoz {
  const SePuedeHablar();
}

/// Esta conversación no tiene carpeta emparejada.
final class SinCarpeta extends LaPuertaDeLaVoz {
  const SinCarpeta();
}

/// La carpeta está en modo solo texto. **Es una negativa, no una preferencia.**
final class LaCarpetaEsDeSoloTexto extends LaPuertaDeLaVoz {
  const LaCarpetaEsDeSoloTexto(this.carpeta);
  final PairedFolder carpeta;
}

/// El cajón de documentos cae dentro de una carpeta en solo texto.
final class ElCajonCaeEnUnaDeSoloTexto extends LaPuertaDeLaVoz {
  const ElCajonCaeEnUnaDeSoloTexto(this.carpeta);
  final PairedFolder carpeta;
}

/// El micrófono está denegado en Ajustes del sistema.
final class ElMicrofonoEstaBloqueado extends LaPuertaDeLaVoz {
  const ElMicrofonoEstaBloqueado();
}

/// Todo lo demás está bien y **solo falta preguntar por el micrófono**.
///
/// Se distingue de [ElMicrofonoEstaBloqueado] porque no es lo mismo: denegado
/// se arregla en Ajustes del sistema y sin decidir se arregla preguntando, y
/// decir lo mismo en los dos casos manda a la gente al sitio equivocado.
final class HayQuePedirElMicrofono extends LaPuertaDeLaVoz {
  const HayQuePedirElMicrofono();
}

/// Los guardias que hay que pasar para abrir la voz, en su orden.
///
/// 🔴 **Esto es la promesa del producto, escrita en código.** El README dice que
/// una carpeta en solo texto «no abre sesión de voz: nada de esa carpeta viaja a
/// Gemini, ni siquiera el audio», y que es «una negativa, no una preferencia».
/// Quien la cumple es esta escalera, y vivía dentro de un `toggleVoice` de 131
/// líneas sin una prueba que la sujetara.
///
/// Va aquí y no en un botón deshabilitado por el mismo motivo por el que ya
/// estaba en el controlador: si viviera en la interfaz, cualquier otro camino
/// que abra sesión —el atajo global, sin ir más lejos— se lo saltaría.
abstract final class SiSePuedeAbrirLaVoz {
  /// Lo que estorba **sin preguntarle nada a nadie**, o `null` si nada estorba.
  ///
  /// 🔴 **Separado del micrófono a propósito, y el orden importa dos veces.**
  /// Consultar el estado del micrófono toca el canal nativo, y pedirlo abre el
  /// diálogo del sistema —que espera a una persona—. Hacer cualquiera de las
  /// dos cosas para acabar negando la sesión por la carpeta es trabajo tirado
  /// en el mejor caso y un permiso pedido en falso en el peor.
  static LaPuertaDeLaVoz? loQueEstorba({
    required PairedFolder? carpeta,
    required PairedFolder? duenoDelCajon,
  }) {
    if (carpeta == null) return const SinCarpeta();
    if (!carpeta.modality.allowsVoice) {
      return LaCarpetaEsDeSoloTexto(carpeta);
    }

    // El cajón de documentos es la única excepción a «ninguna otra carpeta»:
    // viaja como `--add-dir` en todos los encargos, así que si cae dentro de una
    // emparejada en solo texto, esta conversación podría leer de ahí y Gemini
    // narrarlo. La sesión no se abre, que es más estricto que avisar al elegir
    // el cajón — el aviso se ignora y la puerta se queda abierta.
    if (duenoDelCajon != null) {
      return ElCajonCaeEnUnaDeSoloTexto(duenoDelCajon);
    }

    return null;
  }

  /// Y lo que dice el micrófono, una vez que lo demás ya pasó.
  static LaPuertaDeLaVoz porElMicrofono(MicrophoneStatus estado) =>
      switch (estado) {
        MicrophoneStatus.denied => const ElMicrofonoEstaBloqueado(),
        MicrophoneStatus.notAsked => const HayQuePedirElMicrofono(),
        MicrophoneStatus.granted => const SePuedeHablar(),
      };
}

import 'package:nexus/features/assistant/domain/entities/conversation.dart';
import 'package:nexus/features/assistant/domain/usecases/a_que_carpeta_va.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';

/// Qué hacer con un encargo que puede ir a otra carpeta.
sealed class QueHacerConElEncargo {
  const QueHacerConElEncargo();
}

/// Aquí mismo, tal cual llegó.
final class AtenderloAqui extends QueHacerConElEncargo {
  const AtenderloAqui(this.tarea);
  final String tarea;
}

/// A una conversación que ya está abierta sobre esa carpeta.
final class LlevarloA extends QueHacerConElEncargo {
  const LlevarloA(this.conversacion, this.tarea);
  final String conversacion;
  final String tarea;
}

/// No hay ninguna sobre esa carpeta: se abre.
final class AbrirUnaPara extends QueHacerConElEncargo {
  const AbrirUnaPara(this.carpeta, this.tarea);
  final PairedFolder carpeta;
  final String tarea;
}

/// Habría que abrir una y no caben más.
///
/// Se dice en vez de atenderlo aquí en silencio: hacer el trabajo en la carpeta
/// equivocada es el fallo que todo esto viene a evitar.
final class NoCabeOtraConversacion extends QueHacerConElEncargo {
  const NoCabeOtraConversacion(this.carpeta);
  final PairedFolder carpeta;
}

/// Se nombró más de una carpeta: se pregunta.
final class PreguntarPorCual extends QueHacerConElEncargo {
  const PreguntarPorCual(this.carpetas);
  final List<PairedFolder> carpetas;
}

/// Dónde acaba un encargo que nombra una carpeta.
///
/// 🔴 **La regla que manda: nunca se trabaja en la carpeta que no era.** Cuando
/// algo no cuadra —dos carpetas nombradas, o ninguna donde abrir— se dice y no
/// se hace, porque de la carpeta cuelgan la cuenta, el modelo y los permisos: un
/// encargo en la equivocada puede escribir con la cuenta del trabajo en un repo
/// personal, y eso no se deshace pidiéndolo.
abstract final class QueHacerConLoQueSeDijo {
  static QueHacerConElEncargo de(
    AQueCarpetaVa destino, {
    required String frase,
    required String? carpetaDeAqui,
    required Conversations abiertas,
  }) => switch (destino) {
    NoSeNombroCarpeta() => AtenderloAqui(frase),
    SeNombraronVarias(:final carpetas) => PreguntarPorCual(carpetas),
    AEstaCarpeta(:final carpeta, :final tarea) => _hacia(
      carpeta,
      tarea: tarea,
      frase: frase,
      carpetaDeAqui: carpetaDeAqui,
      abiertas: abiertas,
    ),
  };

  static QueHacerConElEncargo _hacia(
    PairedFolder carpeta, {
    required String tarea,
    required String frase,
    required String? carpetaDeAqui,
    required Conversations abiertas,
  }) {
    // Ya se está ahí: no se mueve nada. **Y va la tarea, no la frase entera**:
    // repetir «en nexus» dentro de un encargo que ya corre en nexus es ruido en
    // el prompt, y el prompt se paga.
    //
    // Salvo que la tarea venga vacía —«vete a nexus» estando en nexus—: eso no
    // es un encargo, así que se atiende la frase original y quien la reciba
    // decidirá que no hay nada que hacer.
    if (carpeta.path == carpetaDeAqui) {
      return AtenderloAqui(tarea.isEmpty ? frase : tarea);
    }

    // 🔴 **La que ya está abierta gana, y la más reciente entre ellas.** Abrir
    // una segunda sobre la misma carpeta es legítimo —son sesiones
    // independientes— pero no es lo que se pidió: quien dice «en el front
    // mobile, sigue con esto» quiere la que ya tiene el hilo, no una en blanco
    // que no sabe de qué se hablaba.
    final suyas = [
      for (final c in abiertas.items)
        if (c.folderPath == carpeta.path) c,
    ];
    if (suyas.isNotEmpty) return LlevarloA(suyas.last.id, tarea);

    if (abiertas.items.length >= Conversations.max) {
      return NoCabeOtraConversacion(carpeta);
    }
    return AbrirUnaPara(carpeta, tarea);
  }
}

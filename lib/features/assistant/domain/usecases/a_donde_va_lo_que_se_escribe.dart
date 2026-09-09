import 'package:nexus/features/agenda/domain/usecases/lo_que_se_pregunta_de_la_agenda.dart';
import 'package:nexus/features/artifacts/domain/usecases/lo_que_se_pide_dibujar.dart';
import 'package:nexus/features/assistant/domain/usecases/los_comandos_de_la_casa.dart';
import 'package:nexus/features/history/domain/usecases/el_parte_de_ayer.dart';
import 'package:nexus/features/workspace/domain/usecases/el_comando_directo.dart';

/// Dónde acaba lo que se escribe en el compositor.
sealed class ADondeVa {
  const ADondeVa();
}

/// A git, y la salida se enseña literal.
final class AlGit extends ADondeVa {
  const AlGit(this.comando);
  final ({String comando, List<String> argumentos}) comando;
}

/// A Gemini, a dibujar desde cero.
final class ADibujar extends ADondeVa {
  const ADibujar(this.descripcion);
  final String descripcion;
}

/// A Gemini, encadenando sobre la imagen anterior.
///
/// **Que exista una imagen anterior no se decide aquí.** Esto dice qué se está
/// pidiendo; si hay algo que editar es estado de la conversación, y quien lo
/// sabe es quien la lleva.
final class AEditarLaImagen extends ADondeVa {
  const AEditarLaImagen(this.cambio);
  final String cambio;
}

/// A la agenda que ya está en memoria.
///
/// **Es un candidato, no un destino firme:** si no hay agenda que mirar —avisos
/// apagados, sin carpeta— quien enruta sigue de largo hacia Claude, que sí
/// puede salir a preguntarlo. Lo mismo con [AlParte] y su día sin trabajo.
final class ALaAgenda extends ADondeVa {
  const ALaAgenda();
}

/// Al parte del día ya reunido.
final class AlParte extends ADondeVa {
  const AlParte();
}

/// A la lista de comandos, que se enseña dentro de la conversación.
final class ALaAyuda extends ADondeVa {
  const ALaAyuda();
}

/// A empezar de cero en esta carpeta: el `/clear` de la terminal.
final class AOlvidar extends ADondeVa {
  const AOlvidar();
}

/// El camino normal.
final class AClaude extends ADondeVa {
  const AClaude();
}

/// El orden en que se reconocen los atajos, que es lo que decide de verdad.
///
/// 🔴 **Vivía dentro de un `submit` de 217 líneas**, y no es plumbing: es una
/// precedencia, y equivocarla **secuestra trabajo de verdad**. El propio
/// `LoQueSePreguntaDeLaAgenda` ya lo dice de su lado —«buscar "reunión" dentro
/// del texto convertiría "arregla el bug de la pantalla de reuniones" en una
/// consulta de agenda»—, y aquí es lo mismo un nivel más arriba: qué se mira
/// antes que qué, y con qué condiciones.
///
/// Las dos reglas que no se ven y se rompen solas:
///
/// - **Los adjuntos no valen igual para todos.** Dibujar y editar los admiten
///   —son las imágenes de referencia, o sea material—; la agenda y el parte no,
///   porque quien suelta archivos y escribe «mi agenda» está pidiendo otra cosa.
/// - **El parte no reconoce atajos dentro de sí mismo.** Cuando ya se está
///   redactando uno, `esElParte` apaga todo lo demás: si no, un parte que
///   mencione `/imagen` acabaría dibujando.
abstract final class ADondeVaLoQueSeEscribe {
  static ADondeVa de(
    String frase, {
    required bool esElParte,
    required bool hayAdjuntos,
  }) {
    final limpia = frase.trim();
    if (esElParte) return const AClaude();

    // Primero el de git, y **es el único que puede ir primero sin pensarlo**:
    // `!` no empieza ninguna frase que alguien escriba en serio, así que no
    // puede colisionar con nada de lo de abajo.
    if (ElComandoDirecto.deLaFrase(limpia) case final directo?) {
      return AlGit(directo);
    }

    // Los comandos exactos, que no llevan nada escrito detrás. Van aquí, con
    // los otros de barra y **antes** de las frases naturales: `/parte` tiene
    // que valer aunque la lista de frases del parte cambie mañana. Ver
    // [ElComandoDeLaCasa].
    switch (ElComandoDeLaCasa.deLaFrase(limpia)) {
      case ElComandoDeLaCasa.ayuda:
        return const ALaAyuda();
      case ElComandoDeLaCasa.olvida:
        return const AOlvidar();
      case ElComandoDeLaCasa.parte:
        return const AlParte();
      case ElComandoDeLaCasa.agenda:
        return const ALaAgenda();
      // Los que llevan texto los reconoce su dueño, unas líneas más abajo: aquí
      // no se repite esa decisión.
      case _:
        break;
    }

    if (LoQueSePideDibujar.deLaFrase(limpia) case final descripcion?) {
      return ADibujar(descripcion);
    }
    if (LoQueSePideDibujar.loQueSeCambia(limpia) case final cambio?) {
      return AEditarLaImagen(cambio);
    }

    if (hayAdjuntos) return const AClaude();

    if (LoQueSePreguntaDeLaAgenda.loEstanPidiendo(limpia)) {
      return const ALaAgenda();
    }
    if (ElParteDeAyer.loEstanPidiendo(limpia)) return const AlParte();

    return const AClaude();
  }
}

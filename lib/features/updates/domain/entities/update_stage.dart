import 'package:flutter/foundation.dart';

/// Por dónde va la actualización.
///
/// `sealed` a propósito: la modal decide qué pinta con un `switch` sobre esto, y
/// así el día que Sparkle gane una fase el compilador señala el sitio exacto que
/// falta pintar. Con un enum y un puñado de campos opcionales, ese mismo día se
/// vería una modal vacía y nadie sabría por qué.
@immutable
sealed class UpdateStage {
  const UpdateStage();
}

/// No hay nada en marcha. Es el estado el 99 % del tiempo.
class UpdateIdle extends UpdateStage {
  const UpdateIdle();
}

/// Preguntando. Solo se enseña cuando lo pidió una persona: una comprobación de
/// fondo que saca un cartel es una interrupción sin motivo.
class UpdateChecking extends UpdateStage {
  const UpdateChecking();
}

/// Se preguntó y no hay nada. Se enseña solo tras una comprobación manual,
/// porque un botón que no contesta se lee como roto.
class UpdateUpToDate extends UpdateStage {
  const UpdateUpToDate();
}

/// Hay versión nueva y todavía no se ha dicho nada.
class UpdateFound extends UpdateStage {
  const UpdateFound({
    required this.version,
    this.notes,
    this.bytes,
    this.alreadyDownloaded = false,
  });

  /// La que se ofrece, tal como la enseña el feed: `0.0.3`.
  final String version;

  /// Qué trae, si el feed lo cuenta.
  final String? notes;

  /// Cuánto pesa la descarga, para poder decirlo antes de empezarla.
  final int? bytes;

  /// Si ya venía bajada de una vuelta anterior. Cambia lo que ofrece el botón:
  /// no hay nada que descargar, solo reiniciar.
  final bool alreadyDownloaded;
}

/// Bajando. [total] es `null` mientras el servidor no diga cuánto pesa.
class UpdateDownloading extends UpdateStage {
  const UpdateDownloading({required this.received, this.total});

  final int received;
  final int? total;

  /// `null` cuando no se sabe el total: una barra que finge un porcentaje que no
  /// tiene es peor que una barra indeterminada, que al menos no miente.
  double? get fraction {
    final peso = total;
    if (peso == null || peso <= 0) return null;
    return (received / peso).clamp(0.0, 1.0);
  }
}

/// Descomprimiendo, con su propio progreso: en un paquete de 23 MB esto tarda lo
/// suficiente para que un cartel quieto parezca colgado.
class UpdateExtracting extends UpdateStage {
  const UpdateExtracting({required this.progress});

  final double progress;
}

/// Lista para instalarse, esperando el permiso para reiniciar.
///
/// Es una parada aparte y no un paso automático porque reiniciar tiene un coste
/// real aquí: puede haber un `claude -p` escribiendo archivos.
class UpdateReady extends UpdateStage {
  const UpdateReady();
}

/// Cambiando la app. A partir de aquí no se puede cancelar.
class UpdateInstalling extends UpdateStage {
  const UpdateInstalling();
}

/// Algo falló, con lo que dijo el actualizador.
class UpdateFailed extends UpdateStage {
  const UpdateFailed(this.message);

  final String message;
}

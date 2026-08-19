import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/stats/data/datasources/transcript_data_source.dart';
import 'package:nexus/features/stats/domain/entities/transcript_turn.dart';

/// Los turnos de una cuenta, leídos del disco una sola vez.
///
/// La familia va por directorio de configuración porque cada cuenta guarda los
/// suyos aparte — es lo mismo que separa `work` de `private` en todo lo demás.
///
/// Se cachea mientras Ajustes esté abierto y se tira al cerrarlo: son dos
/// segundos de lectura que no hay por qué repetir al cambiar de pestaña, y
/// treinta mil turnos que no hay por qué guardar el resto de la sesión.
final transcriptTurnsProvider =
    FutureProvider.family<List<TranscriptTurn>, String>(
      (ref, configDir) => const TranscriptDataSource().read(configDir),
    );

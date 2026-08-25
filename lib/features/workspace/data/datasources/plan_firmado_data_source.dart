import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// El plan firmado de una carpeta, tal como lo lee el hook que deniega las escrituras.
///
/// **La app y el hook comparten un archivo, no una base de datos.** El hook es un proceso
/// aparte —lo lanza el CLI, no Nexus— así que lo único que los dos pueden ver es el disco.
/// Y por eso este formato es el contrato: si cambia aquí sin cambiar allí, el gate deja de
/// bloquear **en silencio**, que ya pasó una vez con el nombre del archivo.
@immutable
class PlanFirmado {
  const PlanFirmado({
    required this.carpeta,
    required this.exige,
    this.plan,
    this.firmado,
    this.vale = const Duration(hours: 1),
  });

  factory PlanFirmado.fromJson(Map<String, Object?> j) => PlanFirmado(
    carpeta: (j['carpeta'] as String?) ?? '',
    exige: j['exige'] == true,
    plan: j['plan'] as String?,
    firmado: switch (j['firmado']) {
      final num s => DateTime.fromMillisecondsSinceEpoch(
        (s * 1000).round(),
        isUtc: true,
      ),
      _ => null,
    },
    vale: Duration(seconds: (j['vale'] as num?)?.toInt() ?? 3600),
  );

  final String carpeta;

  /// Si esta carpeta pide plan antes de escribir.
  final bool exige;

  /// Qué se va a hacer, en una frase. Vacío no cuenta como firmado: firmar es decir algo,
  /// no rellenar un campo.
  final String? plan;

  final DateTime? firmado;

  /// Cuánto vale la firma. Caduca a propósito y con el mismo criterio que el permiso de
  /// escritura: uno que no caduca deja de ser una decisión y pasa a ser un ajuste que
  /// alguien puso una vez.
  final Duration vale;

  /// Los segundos desde la época, que es lo que entiende el hook.
  Map<String, Object?> toJson() => {
    'carpeta': carpeta,
    'exige': exige,
    if (plan != null && plan!.trim().isNotEmpty) 'plan': plan!.trim(),
    if (firmado != null) 'firmado': firmado!.millisecondsSinceEpoch ~/ 1000,
    'vale': vale.inSeconds,
  };

  /// Si ahora mismo se puede escribir en esta carpeta.
  bool vigenteEn(DateTime ahora) {
    if (!exige) return true;
    if (plan == null || plan!.trim().isEmpty) return false;
    if (firmado == null) return false;
    return ahora.toUtc().difference(firmado!) <= vale;
  }

  /// Lo que queda de vigencia, o `null` si no aplica. Para poder decirlo en pantalla en
  /// vez de dejar a alguien adivinando cuándo caduca.
  Duration? restanteEn(DateTime ahora) {
    if (!exige || firmado == null) return null;
    final resto = vale - ahora.toUtc().difference(firmado!);
    return resto.isNegative ? Duration.zero : resto;
  }

  PlanFirmado copyWith({bool? exige, String? plan, DateTime? firmado}) =>
      PlanFirmado(
        carpeta: carpeta,
        exige: exige ?? this.exige,
        plan: plan ?? this.plan,
        firmado: firmado ?? this.firmado,
        vale: vale,
      );
}

/// Lee y escribe las marcas de plan que consume el hook.
class PlanFirmadoDataSource {
  const PlanFirmadoDataSource();

  /// El nombre del archivo **no identifica la carpeta**: la carpeta va dentro y se
  /// compara resuelta. La primera versión la codificaba en el nombre con un hash, y
  /// `/var` y `/private/var` acabaron siendo dos carpetas distintas — el gate dejó de
  /// bloquear sin decir nada.
  Directory _dir(String configDir) => Directory('$configDir/nexus-planes');

  Future<PlanFirmado?> leer(String configDir, String carpeta) async {
    final dir = _dir(configDir);
    if (!dir.existsSync()) return null;
    final buscada = _resuelta(carpeta);

    for (final entrada in dir.listSync()) {
      if (entrada is! File || !entrada.path.endsWith('.json')) continue;
      try {
        final leido = jsonDecode(await entrada.readAsString());
        if (leido is! Map) continue;
        final plan = PlanFirmado.fromJson(leido.cast<String, Object?>());
        if (_resuelta(plan.carpeta) == buscada) return plan;
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }

  Future<void> guardar(String configDir, PlanFirmado plan) async {
    final dir = _dir(configDir)..createSync(recursive: true);
    // Un archivo por carpeta, con un nombre estable derivado de ella para no acumular
    // uno nuevo por cada firma. Que el nombre sea legible ayuda a mirar la carpeta y
    // entender qué hay, que es lo contrario de un hash.
    final nombre = _resuelta(plan.carpeta)
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    await File(
      '${dir.path}/$nombre.json',
    ).writeAsString('${jsonEncode(plan.toJson())}\n');
  }

  static String _resuelta(String ruta) {
    if (ruta.isEmpty) return ruta;
    try {
      return Directory(ruta).resolveSymbolicLinksSync();
    } on FileSystemException {
      // La carpeta puede no existir todavía —o ser de otra máquina— y entonces lo mejor
      // que se puede hacer es comparar la ruta tal cual.
      return ruta;
    }
  }
}

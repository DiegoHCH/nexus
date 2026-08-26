import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/workspace/data/datasources/marcas_por_rama.dart';

/// El plan firmado de una carpeta **en una rama**, tal como lo lee el hook que deniega las
/// escrituras.
///
/// **La app y el hook comparten un archivo, no una base de datos.** El hook es un proceso
/// aparte —lo lanza el CLI, no Nexus— así que lo único que los dos pueden ver es el disco.
/// Y por eso este formato es el contrato: si cambia aquí sin cambiar allí, el gate deja de
/// bloquear **en silencio**, que ya pasó una vez con el nombre del archivo.
///
/// Esto es la vista de **una** rama. El archivo del disco lleva la carpeta entera con
/// todas sus ramas dentro, y de armarlo y deshacerlo se encarga [PlanFirmadoDataSource]:
/// quien pinta una pantalla no tiene por qué saber que existen las demás.
@immutable
class PlanFirmado {
  const PlanFirmado({
    required this.carpeta,
    required this.exige,
    this.rama,
    this.plan,
    this.firmado,
    this.vale = const Duration(hours: 8),
  });

  final String carpeta;

  /// La rama a la que pertenece esta firma, o `null` si la carpeta no está en un repo.
  ///
  /// **La exigencia es de la carpeta y la firma es de la rama.** Son dos decisiones de
  /// plazos distintos: que un proyecto pida plan se decide una vez, y qué se va a hacer se
  /// decide por tarea — y una tarea es una rama. Con una sola firma por carpeta, irse a
  /// otra rama a atender una urgencia borraba el plan de lo que estabas haciendo, y al
  /// volver tocaba firmar otra vez algo que seguía siendo verdad.
  final String? rama;

  /// Si esta carpeta pide plan antes de escribir.
  final bool exige;

  /// Qué se va a hacer, en una frase. Vacío no cuenta como firmado: firmar es decir algo,
  /// no rellenar un campo.
  final String? plan;

  final DateTime? firmado;

  /// Cuánto vale la firma. Caduca a propósito y con el mismo criterio que el permiso de
  /// escritura: uno que no caduca deja de ser una decisión y pasa a ser un ajuste que
  /// alguien puso una vez.
  ///
  /// La jornada y no la hora: el plazo tiene que durar lo que dura una tarea. Con una hora
  /// —lo que valía cuando la firma era de la carpeta— dos días de trabajo se firmaban
  /// dieciséis veces, y una firma que se repite dieciséis veces deja de leerse.
  final Duration vale;

  /// La clave bajo la que vive esta firma dentro del archivo.
  String get claveDeRama => MarcasPorRama.clave(rama);

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

  PlanFirmado copyWith({
    bool? exige,
    String? plan,
    DateTime? firmado,
    String? rama,
  }) => PlanFirmado(
    carpeta: carpeta,
    rama: rama ?? this.rama,
    exige: exige ?? this.exige,
    plan: plan ?? this.plan,
    firmado: firmado ?? this.firmado,
    vale: vale,
  );
}

/// Lee y escribe las marcas de plan que consume el hook.
///
/// El archivo de una carpeta es uno solo y lleva **todas** sus ramas:
///
/// ```json
/// {"carpeta": "/ruta", "exige": true, "vale": 28800,
///  "ramas": {"feat/algo": {"plan": "…", "firmado": 1756}}}
/// ```
///
/// Un archivo por rama habría sido más simple de escribir y peor de vivir: `exige` es de
/// la carpeta, así que estaría repetido en todos y encenderlo o apagarlo tendría que
/// recorrerlos —y bastaría con que uno se quedara atrás para que el gate hiciera cosas
/// distintas según la rama en la que estés, sin decir por qué.
class PlanFirmadoDataSource {
  const PlanFirmadoDataSource();

  /// El nombre del archivo **no identifica la carpeta**: la carpeta va dentro y se
  /// compara resuelta. La primera versión la codificaba en el nombre con un hash, y
  /// `/var` y `/private/var` acabaron siendo dos carpetas distintas — el gate dejó de
  /// bloquear sin decir nada.
  Directory _dir(String configDir) => Directory('$configDir/nexus-planes');

  /// La marca de esa carpeta en esa rama, o `null` si la carpeta no tiene ninguna.
  ///
  /// Sin `rama` se lee la firma de una carpeta que no está en un repositorio. Da igual
  /// para `exige`, que es de la carpeta entera: quien solo quiera saber si se exige plan
  /// puede llamar sin rama y no se equivoca.
  Future<PlanFirmado?> leer(
    String configDir,
    String carpeta, {
    String? rama,
  }) async {
    final dir = _dir(configDir);
    if (!dir.existsSync()) return null;
    final buscada = _resuelta(carpeta);

    for (final entrada in dir.listSync()) {
      if (entrada is! File || !entrada.path.endsWith('.json')) continue;
      try {
        final leido = jsonDecode(await entrada.readAsString());
        if (leido is! Map) continue;
        final archivo = leido.cast<String, Object?>();
        if (_resuelta((archivo['carpeta'] as String?) ?? '') != buscada) {
          continue;
        }
        return _desde(archivo, carpeta: carpeta, rama: rama);
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }

  /// Guarda **sin pisar las demás ramas**.
  ///
  /// Se relee el archivo antes de escribir en vez de confiar en lo que la pantalla tenga
  /// en memoria: otra ventana de Nexus puede haber firmado en otra rama de la misma
  /// carpeta mientras esta estaba abierta, y escribir el objeto entero desde memoria le
  /// borraría la firma sin que nada lo dijera.
  Future<void> guardar(String configDir, PlanFirmado plan) async {
    final dir = _dir(configDir)..createSync(recursive: true);
    // Un archivo por carpeta, con un nombre estable derivado de ella para no acumular
    // uno nuevo por cada firma. Que el nombre sea legible ayuda a mirar la carpeta y
    // entender qué hay, que es lo contrario de un hash.
    final archivo = File(
      '${dir.path}/${MarcasPorRama.nombre(plan.carpeta)}.json',
    );

    final ramas = <String, Object?>{};
    if (archivo.existsSync()) {
      try {
        final leido = jsonDecode(await archivo.readAsString());
        if (leido is Map && leido['ramas'] is Map) {
          ramas.addAll((leido['ramas'] as Map).cast<String, Object?>());
        }
      } on FormatException {
        // Un archivo ilegible se rehace. Es nuestro y solo lleva firmas: perder las de
        // otras ramas es molesto, dejar de poder firmar es peor.
      }
    }

    final firmado = plan.firmado;
    if ((plan.plan ?? '').trim().isEmpty || firmado == null) {
      // Sin firma no se deja una entrada vacía: «esta rama existe y no tiene plan» y «esta
      // rama no está» significan lo mismo para el hook, y una de las dos formas sobra.
      ramas.remove(plan.claveDeRama);
    } else {
      ramas[plan.claveDeRama] = {
        'plan': plan.plan!.trim(),
        'firmado': firmado.millisecondsSinceEpoch ~/ 1000,
      };
    }

    await archivo.writeAsString(
      '${jsonEncode({'carpeta': plan.carpeta, 'exige': plan.exige, 'vale': plan.vale.inSeconds, 'ramas': ramas})}\n',
    );
  }

  /// El archivo de una carpeta, leído para una rama.
  ///
  /// El formato viejo —la firma suelta en la raíz, sin `ramas`— se lee como **sin
  /// firmar**: se respeta `exige` y se pide firmar una vez más. Heredar esa firma en todas
  /// las ramas sería justo el fallo que este cambio viene a arreglar.
  PlanFirmado _desde(
    Map<String, Object?> archivo, {
    required String carpeta,
    required String? rama,
  }) {
    final vacio = PlanFirmado(
      carpeta: carpeta,
      rama: rama,
      exige: archivo['exige'] == true,
      vale: Duration(seconds: (archivo['vale'] as num?)?.toInt() ?? 28800),
    );

    final ramas = archivo['ramas'];
    if (ramas is! Map) return vacio;
    final firma = ramas[vacio.claveDeRama];
    if (firma is! Map) return vacio;

    return vacio.copyWith(
      plan: firma['plan'] as String?,
      firmado: switch (firma['firmado']) {
        final num s => DateTime.fromMillisecondsSinceEpoch(
          (s * 1000).round(),
          isUtc: true,
        ),
        _ => null,
      },
    );
  }

  /// Todas las carpetas y ramas que tienen una firma anotada.
  Future<Set<({String carpeta, String? rama})>> carpetasYRamas(
    String configDir,
  ) => MarcasPorRama.claves(_dir(configDir));

  /// Se lleva la firma de esa rama, dejando lo de la carpeta —si exige plan, cada cuánto
  /// caduca— donde estaba. La usa la limpieza de corridas huérfanas.
  Future<void> borrar(String configDir, String carpeta, String? rama) =>
      MarcasPorRama.borrar(_dir(configDir), carpeta, rama);

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

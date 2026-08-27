import 'package:flutter/foundation.dart';

/// Qué puede **salir** de una carpeta hacia el servicio de voz.
///
/// Es el segundo eje de permisos, decidido en i5: no basta con controlar qué
/// puede *hacer* Nexus con una carpeta, porque en cuanto Gemini narra un
/// resultado, lo que Claude leyó del repo viaja hacia Google dentro del
/// `toolResponse`. Restringir solo el micrófono dejaría la fuga abierta por el
/// otro lado, así que en [textOnly] **Gemini no participa**: se trabaja por el
/// camino de escribir → Claude → subtítulo.
enum FolderModality {
  /// Nada sale hacia el servicio de voz. Ni tu micrófono, ni lo que Claude lea.
  textOnly,

  /// Se puede abrir sesión de voz sobre esta carpeta.
  voice;

  bool get allowsVoice => this == FolderModality.voice;
}

/// Una carpeta emparejada: el sitio donde Nexus tiene permiso para trabajar.
@immutable
class PairedFolder {
  const PairedFolder({
    required this.path,
    required this.modality,
    this.claudeProfile,
    this.claudeModel,
    this.claudeEffort,
    this.activeRepo,
    this.blockedCommands = const [],
    this.carpetaDePruebas,
  });

  final String path;
  final FolderModality modality;

  /// Con qué cuenta de Claude se trabaja aquí — el `CLAUDE_CONFIG_DIR` del
  /// perfil—, o `null` para el de siempre.
  ///
  /// Va por carpeta y no por app porque así es como se usa: los repos del
  /// trabajo con la cuenta del trabajo, los personales con la personal. Un
  /// interruptor global obligaría a acordarse de cambiarlo al saltar de
  /// proyecto, y equivocarse ahí significa gastar el cupo de la cuenta que no
  /// era —o que el CLI ni siquiera arranque, si esa no tiene sesión.
  final String? claudeProfile;

  /// Con qué modelo y con cuánto esfuerzo se trabaja aquí, o `null` para dejar
  /// lo que tenga el CLI.
  ///
  /// Va por carpeta por lo mismo que la cuenta: un repo grande pide Opus y una
  /// nota rápida se contesta con Haiku, y tenerlo global obliga a acordarse de
  /// cambiarlo al saltar de proyecto — que es justo cuando no te acuerdas.
  final String? claudeModel;
  final String? claudeEffort;

  /// El repo de dentro sobre el que se trabaja ahora, cuando esta carpeta es
  /// una raíz con varios. `null` = la carpeta entera.
  ///
  /// Importa más de lo que parece: es el directorio con el que arranca Claude,
  /// así que decide dónde ocurre un commit, qué rama se ve y qué reglas se
  /// cargan.
  final String? activeRepo;

  /// Lo que Claude **no** puede ejecutar aquí: fragmentos de comando, uno por
  /// entrada —`build_runner`, `pod install`, `make generate`—.
  ///
  /// Por carpeta porque lo que tarda en un repo no tarda en otro. Y no es un
  /// ruego en el prompt: el CLI los deniega, así que no hay rodeo posible.
  final List<String> blockedCommands;

  /// Dónde viven las pruebas de este proyecto, o `null` para la convención de Maestro.
  ///
  /// **Existe para que las pruebas de dos proyectos no se mezclen nunca.** Sin esto solo
  /// valía `<proyecto>/.maestro/`, así que quien las quiere fuera del repo —para no
  /// ensuciar uno del trabajo— no tenía dónde ponerlas. Apuntando cada proyecto a su
  /// subcarpeta, la separación no es un filtro que pueda fallar: Nexus lista una carpeta
  /// y las demás no las ve.
  ///
  /// Absoluta o con `~` si están fuera; relativa si están dentro —`flows`, que es donde
  /// las tiene más de un repo—. Se sigue listando **plano y sin bajar**, así que los
  /// auxiliares que cada proyecto guarde en un subdirectorio quedan fuera de la lista
  /// solos, que es lo que se quiere: no son pruebas que se lancen, son piezas que otras
  /// llaman con `runFlow`.
  final String? carpetaDePruebas;

  /// Dónde buscar las pruebas, ya resuelta contra el proyecto, la raíz y el home.
  ///
  /// Tres reglas, y en este orden:
  ///
  /// 1. **Lo que declare la carpeta.** Un repo que ya tiene sus pruebas en `flows/` no
  ///    se puede mover, y el ajuste global no puede pisarlo.
  /// 2. **La raíz común, con una subcarpeta por proyecto**: `~/pruebas/nexus`. Es lo que
  ///    permite tenerlas todas juntas y fuera de los repos sin que se mezclen.
  /// 3. **`.maestro/` dentro del proyecto**, la convención de Maestro, para quien no ha
  ///    elegido nada.
  ///
  /// La declaración de la carpeta gana a la raíz a propósito: la raíz es una preferencia
  /// tuya y la declaración es un hecho del repo.
  String pruebasEn(String home, {String? raiz}) {
    final declarada = carpetaDePruebas?.trim();
    if (declarada == null || declarada.isEmpty) {
      final comun = raiz?.trim();
      if (comun != null && comun.isNotEmpty) {
        final base = comun.startsWith('~/')
            ? '$home${comun.substring(1)}'
            : comun;
        return '$base/$name';
      }
      return '$workingDirectory/.maestro';
    }
    if (declarada.startsWith('/')) return declarada;
    if (declarada.startsWith('~/')) return '$home${declarada.substring(1)}';
    // Relativa al sitio donde Claude trabaja, no a la carpeta emparejada: con una raíz de
    // varios repos, las pruebas son del repo elegido y no de la raíz.
    return '$workingDirectory/$declarada';
  }

  /// Dónde trabaja Claude de verdad.
  String get workingDirectory => activeRepo ?? path;

  /// Lo que se enseña en la interfaz: la ruta con `~` en vez del home, que es
  /// como la escribe el mockup y como la lee cualquiera.
  String displayPath(String home) {
    if (home.isNotEmpty && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }

  /// El último tramo de la ruta, para cuando no cabe entera.
  String get name {
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final slash = trimmed.lastIndexOf('/');
    return slash == -1 ? trimmed : trimmed.substring(slash + 1);
  }

  PairedFolder copyWith({
    FolderModality? modality,
    String? claudeProfile,
    String? claudeModel,
    String? claudeEffort,
    String? activeRepo,
    List<String>? blockedCommands,
    String? carpetaDePruebas,
    bool sinCarpetaDePruebas = false,
  }) => PairedFolder(
    path: path,
    modality: modality ?? this.modality,
    claudeProfile: claudeProfile ?? this.claudeProfile,
    claudeModel: claudeModel ?? this.claudeModel,
    claudeEffort: claudeEffort ?? this.claudeEffort,
    activeRepo: activeRepo ?? this.activeRepo,
    blockedCommands: blockedCommands ?? this.blockedCommands,
    carpetaDePruebas: sinCarpetaDePruebas
        ? null
        : (carpetaDePruebas ?? this.carpetaDePruebas),
  );

  Map<String, dynamic> toJson() => {
    'path': path,
    'modality': modality.name,
    if (claudeProfile != null) 'claudeProfile': claudeProfile,
    if (claudeModel != null) 'claudeModel': claudeModel,
    if (claudeEffort != null) 'claudeEffort': claudeEffort,
    if (activeRepo != null) 'activeRepo': activeRepo,
    if (blockedCommands.isNotEmpty) 'blockedCommands': blockedCommands,
    if (carpetaDePruebas != null && carpetaDePruebas!.trim().isNotEmpty)
      'carpetaDePruebas': carpetaDePruebas!.trim(),
  };

  static PairedFolder? fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String?;
    if (path == null || path.isEmpty) return null;
    return PairedFolder(
      path: path,
      claudeProfile: json['claudeProfile'] as String?,
      claudeModel: json['claudeModel'] as String?,
      claudeEffort: json['claudeEffort'] as String?,
      activeRepo: json['activeRepo'] as String?,
      carpetaDePruebas: json['carpetaDePruebas'] as String?,
      blockedCommands: [
        for (final command
            in json['blockedCommands'] as List<dynamic>? ?? const [])
          if (command is String && command.trim().isNotEmpty) command.trim(),
      ],
      // Si el valor guardado no se reconoce se cae al modo restrictivo, no al
      // permisivo: un dato corrupto no puede abrir el micrófono.
      modality: FolderModality.values.firstWhere(
        (value) => value.name == json['modality'],
        orElse: () => FolderModality.textOnly,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PairedFolder && other.path == path && other.modality == modality;

  @override
  int get hashCode => Object.hash(path, modality);
}

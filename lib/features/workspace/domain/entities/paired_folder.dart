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
  }) => PairedFolder(
    path: path,
    modality: modality ?? this.modality,
    claudeProfile: claudeProfile ?? this.claudeProfile,
    claudeModel: claudeModel ?? this.claudeModel,
    claudeEffort: claudeEffort ?? this.claudeEffort,
    activeRepo: activeRepo ?? this.activeRepo,
    blockedCommands: blockedCommands ?? this.blockedCommands,
  );

  Map<String, dynamic> toJson() => {
    'path': path,
    'modality': modality.name,
    if (claudeProfile != null) 'claudeProfile': claudeProfile,
    if (claudeModel != null) 'claudeModel': claudeModel,
    if (claudeEffort != null) 'claudeEffort': claudeEffort,
    if (activeRepo != null) 'activeRepo': activeRepo,
    if (blockedCommands.isNotEmpty) 'blockedCommands': blockedCommands,
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

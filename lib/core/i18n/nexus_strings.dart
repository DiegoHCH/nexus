import 'package:flutter/widgets.dart';

/// Todo lo que la interfaz dice, en los dos idiomas.
///
/// Un diccionario con getters y no archivos `.arb` generados: son ~120 textos
/// de una app de una sola pantalla grande, y así el compilador avisa de lo que
/// falte —añadir un texto obliga a traducirlo— sin arrastrar un paso de
/// generación. Si algún día hay que traducir a un tercer idioma o meter
/// plurales de verdad, ese es el momento de cambiar a `gen_l10n`, no antes.
///
/// El español manda: es el idioma en que está escrito el producto y en el que
/// se piensan los textos. El inglés se traduce de él.
@immutable
abstract class NexusStrings {
  const NexusStrings();

  static const supported = [Locale('es'), Locale('en')];

  static NexusStrings of(Locale locale) => locale.languageCode == 'en'
      ? const NexusStringsEn()
      : const NexusStringsEs();

  /// El código que se le dice a los modelos para que respondan igual que la
  /// interfaz. Sin esto, la app estaría en inglés y la voz seguiría en español.
  String get languageName;

  // Marca y estados
  String get brand;
  String get starting;
  String get asleep;
  String get listening;
  String get working;
  String get speaking;

  // Barra superior e inferior
  String get pairFolder;
  String get noConversation;
  String get textOnly;
  String get readOnly;
  String get canEdit;
  String get canEditExplainer;
  String get readOnlyExplainer;
  String contextUsed(int percent);
  String get attachFile;
  String get orbLabel;
  String get orbHint;

  // Estadísticas de uso, por cuenta.
  String get sectionStats;
  String get statsOverview;
  String get statsModels;
  String get statsRangeAll;
  String get statsRange30;
  String get statsRange7;
  String get statsSessions;
  String get statsMessages;
  String get statsTotalTokens;
  String get statsActiveDays;
  String get statsCurrentStreak;
  String get statsLongestStreak;
  String get statsPeakHour;
  String get statsFavoriteModel;
  String get statsReading;
  String get statsUnreadable;
  String get statsNothingYet;
  String get statsNoAccounts;
  String statsCachedFootnote(String amount);
  String statsDayTooltip(String day, int messages);
  String statsInOut(String input, String output);

  // Superpoderes: servidores MCP de cada cuenta.
  String get sectionSuperpowers;
  String get sectionAppearance;
  String get themeTitle;
  String get accentTitle;
  String get accentExplainer;
  String get accentPick;
  String get accentAdjusted;
  String get accentReset;
  String get accentInDark;
  String get accentInLight;
  String get accentNameRed;
  String get accentNameOrange;
  String get accentNameAmber;
  String get accentNameLime;
  String get accentNameGreen;
  String get accentNameEmerald;
  String get accentNameCyan;
  String get accentNameBlue;
  String get accentNameIndigo;
  String get accentNameViolet;
  String get accentNameMagenta;
  String get accentNameRose;
  String get accentNameGrey;
  String get themeExplainer;
  String get themeSystem;
  String get themeLight;
  String get themeDark;
  String get mcpExplainer;
  String get mcpInstalled;
  String get mcpNone;
  String get mcpCatalog;
  String get mcpManual;
  String get mcpNameHint;
  String get mcpSpecHint;
  String get mcpAdd;
  String get mcpRemove;
  String get mcpCheck;
  String get mcpCheckNote;
  String get mcpChecking;
  String get mcpCheckFailed;

  // Superpoderes: skills instaladas en la cuenta.
  String get superpowersMcp;

  /// Instalar en todas las cuentas de golpe.
  ///
  /// Existe porque lo instalado en una cuenta es **invisible** para las carpetas de
  /// otra, y el síntoma no menciona cuentas: «en esta carpeta funciona y en esta no».
  String get superpowersEverywhere;

  /// Y el aviso que lo explica sin tener que descubrirlo.
  String get superpowersOnlyHere;
  String get superpowersSkills;
  String get skillsExplainer;
  String get skillsInstalled;
  String get skillsNone;
  String get skillsFromRepo;
  String get skillsSearchHint;
  String skillsCatalog(int total);
  String skillsMore(int rest);
  String get skillsBrowse;
  String get skillsInstall;
  String get skillsUpdate;
  String get skillsRemove;
  String get skillsFetching;
  String get skillsRepoFailed;
  String get skillsOwn;
  String get skillsOwnHint;
  String get skillsCreate;

  // Superpoderes: plugins y marketplaces.
  String get superpowersPlugins;
  String get pluginsExplainer;
  String get pluginsInstalled;
  String get pluginsNone;
  String get pluginsLoading;
  String get pluginsMarketplaces;
  String get pluginsMarketplaceHint;
  String get pluginsAddMarketplace;
  String get pluginsRemoveMarketplace;
  String get pluginsSearchHint;
  String get pluginsInstall;
  String get pluginsUninstall;
  String get pluginsEnable;
  String get pluginsDisable;
  String get pluginsUpdate;
  String get pluginsDetails;
  String get pluginsNoDetails;
  String get close;
  String pluginsCatalog(int total);
  String pluginsMore(int rest);

  // Los documentos generados.
  String get artifacts;
  String get noProject;
  String get artifactsExplainer;
  String get artifactsNoFolder;
  String get artifactsEmpty;
  String get artifactsChoose;
  String get artifactsChange;
  String get artifactsReveal;
  String get artifactsTrash;

  /// Lo que se lee mientras se arrastra un archivo por encima del compositor.
  String get dropHere;

  /// La cabecera de la lista de rutas que acompaña al encargo.
  String get attachedFilesLabel;
  String get chooseFolder;
  String get noGitRepo;
  String changedFiles(int count);
  String get changesTitle;
  String get newFile;
  String blockedTitle(String folder);
  String get blockedExplainer;
  String get blockedHint;
  String get addFolderShort;
  String get openSettings;
  String get statusTalk;
  String get statusShow;
  String get statusQuit;
  String get errandDone;
  String get errandFailed;
  String get modelTitle;
  String get effortTitle;
  String get effortFaster;
  String get effortSmarter;
  String get contextWindow;
  String get usageLimits;
  String get usageFiveHour;
  String get usageWeekly;
  String get usageUnavailable;

  /// Hay sesión: lo que caducó es el acceso, y lo renueva el CLI en cuanto
  /// se use esa cuenta. Decirlo aparte importa porque la frase de al lado
  /// —«no tiene sesión abierta»— manda a iniciar sesión, y aquí no hay nada
  /// que hacer.
  String get usageStale;

  /// Hay con qué preguntar, pero el servicio no contestó.
  String get usageUnreachable;

  /// Para el hueco del **valor** de un medidor, que es de dos o tres
  /// palabras. [usageUnavailable] explica lo de la cuenta y es una frase
  /// entera: metida ahí desbordaba el panel por 192 px, y encima hablaba de
  /// la sesión de la cuenta en el medidor de la ventana de contexto, donde
  /// lo único cierto es que todavía no ha habido turno.
  String get noReadingYet;
  String resetsIn(String when);
  String get sayStopToInterrupt;
  String get stopWithShortcut;
  String get workingCancelHint;
  String get micOpenHint;
  String get noFolderNothingToTouch;
  String canEditFilesIn(String folder);
  String readOnlyIn(String folder);

  // Conversaciones
  String get openAnotherConversation;
  String get newConversation;
  String get pairAFolderToStart;
  String get askSomething;
  String get you;
  String get nexus;

  // Caja de escribir
  String get composerHint;
  String get clearWhatYouWrote;

  // Actividad
  String get rightNow;
  String get noStepsYet;
  String get stopButton;
  String get writesTag;
  String get ranLabel;
  String get returnedLabel;
  String get stillRunning;
  String get waitingForOtherConversation;
  String get waitingByVoice;
  String get noFolderForConversation;
  String textOnlyFolder(String folder);
  String textOnlyArtifactsFolder(String folder);
  String compacting(int percent);
  String compacted(int before, int after);

  /// Se comprimió, pero todavía no hay medida nueva: llega con el turno
  /// siguiente. Decir una cifra inventada sería peor que no darla.
  String get compactedUnknown;

  // Historial
  String get history;
  String get historyExplainer;
  String get nothingAskedYet;
  String startFromScratchIn(String folder);
  String get conversationForgotten;

  // Ajustes
  String get settings;
  String get closeEsc;
  String get sectionVoice;
  String get sectionPermissions;
  String get sectionLanguage;
  String get sectionHistory;
  String get sectionMobile;
  String get channelTitle;
  String get channelExplainer;
  String get channelSwitch;
  String get channelStarting;
  String get channelListeningAt;
  String get channelToken;
  String get channelCopyToken;
  String get channelRotateToken;
  String get channelRotateWarning;
  String get channelNeedsTailscale;
  String get channelPortBusy;
  String get channelUnknownProblem;
  String get channelNoPhoneYet;
  String get channelQrExplainer;
  String get phraseTitle;
  String get phraseExplainer;
  String get phraseDefined;
  String get phraseMissing;
  String get phraseDefine;
  String get phraseChange;
  String get phraseRemove;
  String get phraseTooShort;
  String get phraseSave;
  String get phraseChangeWarning;
  String get sectionModel;
  String get nexusVoice;
  String get audioOutput;
  String get audioOutputExplainer;
  String get audioOutputSystem;
  String get voiceExplainer;
  String get filePermissionsTitle;
  String get filePermissionsExplainer;
  String get foldersWithPermission;
  String get noFoldersYet;
  String get addFolder;
  String get foldersExplainer;
  String get isActiveFolder;
  String get workHere;
  String get remove;
  String get voiceAllowedExplainer;
  String get textOnlyExplainer;
  String get languageTitle;
  String get languageExplainer;
  String get languageSystem;
  String get languageSpanish;
  String get languageEnglish;

  // Archivo de conversaciones
  String get archiveTitle;
  String get archiveExplainer;
  String get archiveNone;
  String get archiveFailedLocal;
  String archiveFailedExternal(String destination);
  String archiveFailedBoth(String destination);
  String get archiveNoneHint;
  String get archiveFolder;
  String get archiveFolderHint;
  String get archiveObsidian;
  String get archiveObsidianHint;
  String get archiveNotion;
  String get archiveNotionHint;
  String get archiveChooseFolder;
  String get archiveNoFolderYet;
  String archiveLayout(String folder);
  String get notionToken;
  String get notionTokenHint;
  String get notionTokenExplainer;
  String get notionPage;
  String get notionPageHint;
  String get notionPageExplainer;
  String get notionReady;
  String get notionMissing;
  String get claudeAccount;
  String get claudeAccountDefault;
  String get deleteConversation;
  String get deleteForReal;
  String get cancel;
  String claudeAccountSignedOut(String name);

  // Configuración inicial
  String get beforeWeStart;
  String get setupTitle;

  // La comprobación de arranque (a3): Claude Code es la mitad del trabajo y no
  // se comprobaba nunca.
  String get readinessTitle;

  // El tour de la primera vez (a3, pieza 2): cuatro paradas, ancladas en piezas
  // que un recién llegado sí tiene en pantalla.
  String get tourOrbTitle;
  String get tourOrbBody;
  String get tourComposerTitle;
  String get tourComposerBody;
  String get tourDockTitle;
  String get tourDockBody;
  String get tourMeterTitle;
  String get sectionHelp;
  String get helpTourTitle;
  String get helpTourExplainer;
  String get helpTourAction;
  String get versionLabel;
  String updateAvailable(String version);
  String get updateChecking;
  String get updateCheckNow;
  String get updateUpToDate;
  String updateUpToDateBody(String version);
  String get updateFoundTitle;
  String updateWeight(String size);
  String updateDownloadedOf(String done, String total);
  String get updateLater;
  String get updateInstall;
  String get updateRestart;
  String get updateDownloading;
  String get updateExtracting;
  String get updateReadyTitle;
  String get updateReadyBody;
  String get updateInstalling;
  String get updateInstallingBody;
  String get updateFailedTitle;
  String get updateFailedBody;
  String get updateRetry;
  String get updateMoveTitle;
  String get updateMoveBody;
  String get guideNeedsTitle;
  String get guideNeedsBody;
  String get guidePrivacyTitle;
  String get guidePrivacyBody;
  String get guidePiecesTitle;
  String get guidePiecesBody;
  String get guideTroubleTitle;
  String get guideTroubleBody;
  String get tourMeterBody;
  String get tourNext;
  String get tourDone;
  String get tourSkip;
  String tourStep(int current, int total);
  String get readinessExplainer;
  String get readinessCliMissing;
  String get readinessCliMissingFix;
  String get readinessSessionMissing;
  String get readinessSessionMissingFix;
  String get readinessHowToInstall;
  String get readinessRecheck;
  String get readinessContinueAnyway;
  String get readinessContinueHint;
  String get setupExplainer;
  String get startUsingNexus;
  String get changeLaterHint;
  String get request;
  String get micPending;
  String get micPendingExplainer;
  String get micAsking;
  String get micAskingExplainer;
  String get micGranted;
  String get micGrantedExplainer;
  String get micDenied;
  String get microphoneBlocked;
  String get micDeniedShort;
  String get micDeniedExplainer;
  String get microphone;
  String get iHearYou;
  String get workFolder;
  String get choose;
  String get chosen;
  String get workFolderTitle;
  String get workFolderExplainer;
  String get geminiKey;
  String get geminiKeyHint;
  String get geminiKeyExplainer;
  String get getFreeKey;
  String keySaveFailed(String error);
}

class NexusStringsEs extends NexusStrings {
  const NexusStringsEs();

  @override
  String get languageName => 'español';

  @override
  String get brand => 'N E X U S';
  @override
  String get starting => 'INICIANDO';
  @override
  String get asleep => 'Dormido';
  @override
  String get listening => 'Escuchando';
  @override
  String get working => 'Trabajando';
  @override
  String get speaking => 'Hablando';

  @override
  String get pairFolder => 'EMPAREJAR CARPETA';
  @override
  String get noConversation => 'sin conversación';
  @override
  String get textOnly => 'SOLO TEXTO';
  @override
  String get readOnly => 'SOLO LEER';
  @override
  String get canEdit => 'PUEDE EDITAR';
  @override
  String get canEditExplainer => 'Modifica archivos sin preguntar';
  @override
  String get readOnlyExplainer => 'Lee y ejecuta, pero no escribe';
  @override
  String contextUsed(int percent) =>
      'Contexto ocupado: $percent %. Al 85 % la conversación se comprime sola.';
  @override
  String get attachFile => 'Adjuntar un archivo';
  @override
  String get orbLabel => 'Orbe de Nexus';
  @override
  String get orbHint => 'Actívalo para hablarle. También responde a ⌥Espacio.';
  @override
  String get sectionStats => 'Estadísticas';
  @override
  String get statsOverview => 'Resumen';
  @override
  String get statsModels => 'Modelos';
  @override
  String get statsRangeAll => 'Todo';
  @override
  String get statsRange30 => '30d';
  @override
  String get statsRange7 => '7d';
  @override
  String get statsSessions => 'Sesiones';
  @override
  String get statsMessages => 'Mensajes';
  @override
  String get statsTotalTokens => 'Tokens';
  @override
  String get statsActiveDays => 'Días activos';
  @override
  String get statsCurrentStreak => 'Racha actual';
  @override
  String get statsLongestStreak => 'Racha más larga';
  @override
  String get statsPeakHour => 'Hora punta';
  @override
  String get statsFavoriteModel => 'Modelo favorito';
  @override
  String get statsReading => 'Leyendo los transcritos…';
  @override
  String get statsUnreadable =>
      'No se pudieron leer los transcritos de esta cuenta.';
  @override
  String get statsNothingYet => 'Todavía no hay nada que contar en este tramo.';
  @override
  String get statsNoAccounts => 'No hay ninguna cuenta de Claude configurada.';
  @override
  String statsCachedFootnote(String amount) =>
      'Además, $amount de tokens leídos o escritos en caché — fuera del total '
      'porque lo eclipsaría.';
  @override
  String statsDayTooltip(String day, int messages) =>
      '$day · $messages mensajes';
  @override
  String statsInOut(String input, String output) =>
      '$input entrada · $output salida';
  @override
  String get sectionSuperpowers => 'Superpoderes';
  @override
  String get sectionAppearance => 'Apariencia';
  @override
  String get themeTitle => 'Claro u oscuro';
  @override
  String get accentTitle => 'Color de acento';
  @override
  String get accentExplainer =>
      'El tono del orbe y de todo lo que resalta. Eliges el color; el brillo lo '
      'ajusta la app para que se lea en el tema claro y en el oscuro.';
  @override
  String get accentPick => 'Elegir el color';
  @override
  String get accentAdjusted =>
      'Se ajusta el brillo, no el color: sobre el vacío hace falta un tono más '
      'claro y sobre fondo claro uno más oscuro. El matiz que elijas no se toca.';
  @override
  String get accentReset => 'Volver al original';
  @override
  String get accentInDark => 'En oscuro';
  @override
  String get accentInLight => 'En claro';
  @override
  String get accentNameRed => 'Rojo';
  @override
  String get accentNameOrange => 'Naranja';
  @override
  String get accentNameAmber => 'Ámbar';
  @override
  String get accentNameLime => 'Lima';
  @override
  String get accentNameGreen => 'Verde';
  @override
  String get accentNameEmerald => 'Esmeralda';
  @override
  String get accentNameCyan => 'Cian';
  @override
  String get accentNameBlue => 'Azul';
  @override
  String get accentNameIndigo => 'Índigo';
  @override
  String get accentNameViolet => 'Violeta';
  @override
  String get accentNameMagenta => 'Magenta';
  @override
  String get accentNameRose => 'Rosa';
  @override
  String get accentNameGrey => 'Gris';
  @override
  String get themeExplainer =>
      'La app nace oscura porque es un HUD, y de noche eso se agradece. Pero a '
      'pleno día un fondo negro se lee peor, y nadie va a cambiar el tema del '
      'Mac entero para eso: aquí se elige aparte.';
  @override
  String get themeSystem => 'El del sistema';
  @override
  String get themeLight => 'Claro';
  @override
  String get themeDark => 'Oscuro';
  @override
  String get mcpExplainer =>
      'Un servidor MCP le da a Claude manos fuera del disco: un navegador, la '
      'documentación de una librería, tu Jira. Se configuran por cuenta.';
  @override
  String get mcpInstalled => 'Puestos en esta cuenta';
  @override
  String get mcpNone => 'Ninguno todavía.';
  @override
  String get mcpCatalog => 'Para poner de un clic';
  @override
  String get mcpManual => 'Otro, a mano';
  @override
  String get mcpNameHint => 'nombre';
  @override
  String get mcpSpecHint => 'https://… o el comando que lo arranca';
  @override
  String get mcpAdd => 'Añadir';
  @override
  String get mcpRemove => 'Quitar';
  @override
  String get mcpCheck => 'Comprobar';
  @override
  String get mcpCheckNote =>
      'Pregunta a cada servidor si responde. Tarda, y trae también los '
      'conectores de tu cuenta de claude.ai.';
  @override
  String get mcpChecking => 'Preguntando a cada uno…';
  @override
  String get mcpCheckFailed => 'El CLI no pudo dar la lista.';
  @override
  String get superpowersMcp => 'Servidores MCP';

  @override
  String get superpowersEverywhere => 'En todas las cuentas';

  @override
  String get superpowersOnlyHere =>
      'Lo que instales aquí solo lo verán las carpetas de esta cuenta — también sus '
      'encargos, que corren con la cuenta de su carpeta.';
  @override
  String get superpowersSkills => 'Skills';
  @override
  String get skillsExplainer =>
      'Una skill es un procedimiento escrito que el agente activa solo cuando '
      'la tarea lo pide. Instalada en la cuenta la usa cualquier proyecto; '
      'escrita dentro de un repo, solo ese.';
  @override
  String get skillsInstalled => 'Instaladas en esta cuenta';
  @override
  String get skillsNone => 'Ninguna todavía.';
  @override
  String get skillsFromRepo => 'Traer de un repositorio';
  @override
  String get skillsSearchHint => 'buscar entre las del repo';
  @override
  String skillsCatalog(int total) => 'Las que trae el repo ($total)';
  @override
  String skillsMore(int rest) => 'Y $rest más. Busca para verlas.';
  @override
  String get skillsBrowse => 'Ver qué trae';
  @override
  String get skillsInstall => 'Instalar';
  @override
  String get skillsUpdate => 'Actualizar';
  @override
  String get skillsRemove => 'Quitar';
  @override
  String get skillsFetching => 'Trayendo el repositorio…';
  @override
  String get skillsRepoFailed => 'No se pudo leer ese repositorio.';
  @override
  String get skillsOwn => 'Escribir una propia';
  @override
  String get skillsOwnHint => 'cómo se llama';
  @override
  String get skillsCreate => 'Crear y abrir';
  @override
  String get superpowersPlugins => 'Plugins';
  @override
  String get pluginsExplainer =>
      'Un plugin reparte skills, agentes y comandos juntos. Salen de los '
      'marketplaces que tengas dados de alta.';
  @override
  String get pluginsInstalled => 'Instalados en esta cuenta';
  @override
  String get pluginsNone => 'Ninguno todavía.';
  @override
  String get pluginsLoading => 'Preguntando al CLI…';
  @override
  String get pluginsMarketplaces => 'Marketplaces';
  @override
  String get pluginsMarketplaceHint => 'usuario/repo, o una URL';
  @override
  String get pluginsAddMarketplace => 'Dar de alta';
  @override
  String get pluginsRemoveMarketplace => 'Quitar el marketplace';
  @override
  String get pluginsSearchHint => 'buscar entre los disponibles';
  @override
  String get pluginsInstall => 'Instalar';
  @override
  String get pluginsUninstall => 'Desinstalar';
  @override
  String get pluginsEnable => 'Encender';
  @override
  String get pluginsDisable => 'Apagar sin desinstalar';
  @override
  String get pluginsUpdate => 'Actualizar';
  @override
  String get pluginsDetails => 'Qué trae y cuánto contexto ocupa';
  @override
  String get pluginsNoDetails => 'El CLI no dio detalles de este plugin.';
  @override
  String get close => 'Cerrar';
  @override
  String pluginsCatalog(int total) => 'Disponibles ($total)';
  @override
  String pluginsMore(int rest) => 'Y $rest más. Busca para verlos.';
  @override
  String get artifacts => 'Documentos';
  @override
  String get noProject => 'Sin proyecto';
  @override
  String get artifactsExplainer =>
      'La carpeta para lo que no es de ningún proyecto: ahí trabajan las '
      'conversaciones sin proyecto y ahí deja Claude lo que genere.';
  @override
  String get artifactsNoFolder =>
      'Elige una carpeta para lo que no es de ningún proyecto. Ahí trabajarán '
      'las conversaciones sin proyecto y ahí dejará Claude lo que genere.';
  @override
  String get artifactsEmpty => 'Todavía no hay nada en esa carpeta.';
  @override
  String get artifactsChoose => 'Elegir carpeta';
  @override
  String get artifactsChange => 'Cambiar de carpeta';
  @override
  String get artifactsReveal => 'Enseñar en el Finder';
  @override
  String get artifactsTrash => 'Mover a la papelera';
  @override
  String get dropHere => 'Suéltalo aquí';
  @override
  String get attachedFilesLabel => 'Archivos adjuntos:';
  @override
  String get chooseFolder => 'Elegir carpeta';
  @override
  String get noGitRepo => 'sin git';
  @override
  String changedFiles(int count) => count == 1
      ? 'VER EL ARCHIVO QUE TOCÓ'
      : 'VER LOS $count ARCHIVOS QUE TOCÓ';
  @override
  String get changesTitle => 'LO QUE CAMBIÓ EN ESTA TAREA';
  @override
  String get newFile => 'nuevo';
  @override
  String blockedTitle(String folder) => 'COMANDOS BLOQUEADOS EN $folder';
  @override
  String get blockedExplainer =>
      'Uno por línea, y basta con un trozo del comando. No es un ruego: el CLI '
      'los deniega, así que no hay rodeo. Claude hará todo lo demás y terminará '
      'diciéndote el comando exacto para que lo lances tú. Con # se comenta.';
  @override
  String get blockedHint => 'build_runner\npod install\nmake generate';
  @override
  String get addFolderShort => 'Emparejar otra carpeta';
  @override
  String get openSettings => 'Ajustes…';
  @override
  String get statusTalk => 'Hablar con Nexus';
  @override
  String get statusShow => 'Abrir la ventana';
  @override
  String get statusQuit => 'Salir de Nexus';
  @override
  String get errandDone => 'El encargo terminó.';
  @override
  String get errandFailed => 'El encargo no se pudo terminar.';
  @override
  String get modelTitle => 'Modelo';
  @override
  String get effortTitle => 'Esfuerzo';
  @override
  String get effortFaster => 'Más rápido';
  @override
  String get effortSmarter => 'Más listo';
  @override
  String get contextWindow => 'Ventana de contexto';
  @override
  String get usageLimits => 'Tu cupo de la suscripción';
  @override
  String get usageFiveHour => 'Límite de 5 horas';
  @override
  String get usageWeekly => 'Semanal';
  @override
  String get usageUnavailable =>
      'Sin dato: esa cuenta no tiene sesión abierta.';
  @override
  String get usageStale =>
      'Sin dato por ahora: la sesión sigue abierta, pero su acceso caducó. '
      'Se actualiza en cuanto uses esta cuenta.';
  @override
  String get usageUnreachable => 'Sin dato: no se pudo preguntar por el cupo.';
  @override
  String get noReadingYet => 'Sin dato';
  @override
  String resetsIn(String when) => 'Se renueva $when';
  @override
  String get sayStopToInterrupt => 'Di «para» para interrumpir';
  @override
  String get stopWithShortcut => 'Detener con ⌘.';
  @override
  String get workingCancelHint => 'TRABAJANDO · ⌥ESPACIO PARA CANCELAR';
  @override
  String get micOpenHint => 'MICRÓFONO ABIERTO · SE CIERRA SOLO AL CALLARTE';
  @override
  String get noFolderNothingToTouch =>
      'Sin carpeta emparejada — nada que tocar todavía';
  @override
  String canEditFilesIn(String folder) => 'Puede editar archivos en $folder';
  @override
  String readOnlyIn(String folder) => 'Solo lectura en $folder';

  @override
  String get openAnotherConversation => 'Abrir otra conversación';
  @override
  String get newConversation => 'NUEVA';
  @override
  String get pairAFolderToStart => 'EMPAREJA UNA CARPETA PARA EMPEZAR';
  @override
  String get askSomething =>
      'PÍDELE ALGO — POR VOZ CON ⌥ESPACIO O ESCRIBIENDO ABAJO';
  @override
  String get you => 'TÚ';
  @override
  String get nexus => 'NEXUS';

  @override
  String get composerHint =>
      'Escribe una instrucción…   ⇧↵ para salto de línea';
  @override
  String get clearWhatYouWrote => 'Borrar lo escrito';

  @override
  String get rightNow => 'AHORA MISMO';
  @override
  String get noStepsYet =>
      'Pensando. Los pasos aparecen aquí en cuanto empiece a tocar algo — hay encargos que se resuelven sin abrir nada.';
  @override
  String get stopButton => 'DETENER  ⌘.';
  @override
  String get writesTag => 'ESCRIBE';
  @override
  String get ranLabel => 'SE EJECUTÓ';
  @override
  String get returnedLabel => 'DEVOLVIÓ';
  @override
  String get stillRunning => 'todavía corriendo…';
  @override
  String get waitingForOtherConversation =>
      'Esperando a la otra conversación sobre esta carpeta';
  @override
  String get waitingByVoice =>
      'Espero turno: hay otra conversación trabajando en esa carpeta.';
  @override
  String get noFolderForConversation =>
      'Esta conversación no tiene carpeta emparejada: no hay dónde trabajar.';
  @override
  String textOnlyFolder(String folder) =>
      'La carpeta $folder está en modo solo texto, así que no se abre el '
      'micrófono. Escríbele por abajo o cambia el modo en Ajustes.';

  @override
  String textOnlyArtifactsFolder(String folder) =>
      'La carpeta de salida «$folder» es de solo texto, y viaja en todos los '
      'encargos: lo que se guarde ahí podría acabar narrado. La voz no se abre '
      'hasta que la cambies o le des modo voz.';
  @override
  String compacting(int percent) =>
      'Contexto al $percent %: comprimiendo la conversación para seguir sin '
      'perder el hilo';
  @override
  String get compactedUnknown =>
      'Conversación comprimida. La medida del contexto se actualiza en el '
      'siguiente turno.';
  @override
  String compacted(int before, int after) =>
      'Conversación comprimida: el contexto baja del $before % al $after %. '
      'Claude conserva un resumen de lo hablado.';

  @override
  String get history => 'HISTORIAL';
  @override
  String get historyExplainer =>
      'De esta carpeta, y se conserva entre arranques. Claude retoma la '
      'conversación anterior, así que sabe lo que ya hicisteis.';
  @override
  String get nothingAskedYet => 'Todavía no le has pedido nada.';
  @override
  String startFromScratchIn(String folder) =>
      'QUE CLAUDE OLVIDE LO HABLADO EN $folder';
  @override
  String get conversationForgotten =>
      'Conversación olvidada: la próxima empieza de cero.';

  @override
  String get settings => 'AJUSTES';
  @override
  String get closeEsc => 'CERRAR  ESC';
  @override
  String get sectionVoice => 'Voz';
  @override
  String get sectionPermissions => 'Permisos';
  @override
  String get sectionLanguage => 'Idioma';
  @override
  String get sectionMobile => 'Móvil';
  @override
  String get channelTitle => 'El canal del teléfono';
  @override
  String get channelExplainer =>
      'Escucha solo por Tailscale, nunca en la red local. Con eso el cifrado y la '
      'identidad ya los pone WireGuard, y no hacen falta certificados.';
  @override
  String get channelSwitch => 'Aceptar conexiones del teléfono';
  @override
  String get channelStarting => 'Abriendo el canal…';
  @override
  String get channelListeningAt => 'Escuchando en';
  @override
  String get channelToken => 'Token';
  @override
  String get channelCopyToken => 'Copiar';
  @override
  String get channelRotateToken => 'Rotar';
  @override
  String get channelRotateWarning =>
      'Rotarlo cierra las conexiones abiertas y deja fuera a todos los teléfonos: '
      'es la forma de revocar el acceso.';
  @override
  String get channelNeedsTailscale =>
      'No encuentro Tailscale en este Mac. El canal solo escucha por ahí, así que '
      'hay que instalarlo y entrar con tu cuenta — en el Mac y en el teléfono.';
  @override
  String get channelPortBusy =>
      'El puerto 7845 está ocupado. Casi siempre es otra copia de Nexus abierta: '
      'ciérrala y vuelve a encenderlo.';
  @override
  String get channelUnknownProblem =>
      'El canal no pudo abrirse. El motivo queda en el registro del sistema.';
  @override
  @override
  String get channelQrExplainer =>
      'Escanéalo desde la app del teléfono. Lleva esta dirección y este token, así '
      'que es lo mismo que teclearlos — solo que sin teclear 43 caracteres.';
  @override
  String get channelNoPhoneYet =>
      'La app del teléfono ya existe: se instala desde el repositorio, se empareja '
      'pegando aquí la dirección y el token, y necesita Tailscale en el teléfono '
      'igual que aquí. Lo que no hay todavía es una versión publicada del móvil.';
  @override
  String get phraseTitle => 'Frase de escritura';
  @override
  String get phraseExplainer =>
      'El token deja entrar al teléfono; esta frase es la que le deja escribir. No '
      'se guarda en el teléfono: se teclea cuando hace falta y la comprueba este '
      'Mac, así que llevarse el teléfono no basta para escribir.';
  @override
  String get phraseDefined => 'Definida';
  @override
  String get phraseMissing =>
      'Sin definir: el teléfono puede pedir cosas y leer, pero no escribir.';
  @override
  String get phraseDefine => 'Definir';
  @override
  String get phraseChange => 'Cambiar';
  @override
  String get phraseRemove => 'Quitar';
  @override
  String get phraseTooShort => 'Al menos ocho caracteres.';
  @override
  String get phraseSave => 'Guardar';
  @override
  String get phraseChangeWarning =>
      'Cambiarla o quitarla cierra el permiso de escritura que estuviera abierto.';
  @override
  String get sectionModel => 'Modelo';
  @override
  String get nexusVoice => 'VOZ DE NEXUS';
  @override
  String get audioOutput => 'POR DÓNDE SUENA';
  @override
  String get audioOutputExplainer =>
      'Vale desde la próxima vez que le hables: el aparato se fija al montar el '
      'audio. Con «el del sistema», cambiar de auriculares cambia también esto.';
  @override
  String get audioOutputSystem => 'El del sistema';
  @override
  String get voiceExplainer =>
      'Se fija al abrir la sesión, así que un cambio vale desde la próxima vez '
      'que le hables.';
  @override
  String get filePermissionsTitle => 'PERMISOS SOBRE TUS ARCHIVOS';
  @override
  String get filePermissionsExplainer =>
      'Este interruptor está siempre visible en la barra superior. En «solo '
      'leer», Nexus puede abrir archivos y correr comandos que no escriben; en '
      '«puede editar», también modifica archivos.';
  @override
  String get foldersWithPermission => 'CARPETAS CON PERMISO';
  @override
  String get noFoldersYet =>
      'Todavía no hay ninguna. Sin carpeta emparejada no hay dónde trabajar: '
      'Claude correría sobre la raíz del disco.';
  @override
  String get addFolder => 'AÑADIR CARPETA';
  @override
  String get foldersExplainer =>
      'Cada conversación trabaja sobre una carpeta y **solo** sobre esa: es la '
      'frontera del contexto. Si las reglas de un repo viven fuera de él —un '
      'ai-context al lado— empareja la carpeta padre, no las dos por separado.';
  @override
  String get isActiveFolder => 'Es la carpeta activa';
  @override
  String get workHere => 'Trabajar aquí';
  @override
  String get remove => 'Quitar';
  @override
  String get voiceAllowedExplainer =>
      'Se puede hablar con esta carpeta: tu voz y lo que Claude lea salen hacia '
      'Google';
  @override
  String get textOnlyExplainer =>
      'Solo texto: nada de esta carpeta sale hacia el servicio de voz';
  @override
  String get languageTitle => 'IDIOMA';
  @override
  String get languageExplainer =>
      'Cambia la interfaz y también cómo te responden: la voz y Claude '
      'contestan en el idioma elegido.';
  @override
  String get languageSystem => 'El del sistema';
  @override
  String get languageSpanish => 'Español';
  @override
  String get languageEnglish => 'English';

  @override
  String get sectionHistory => 'Historial';
  @override
  String get archiveTitle => 'DÓNDE SE GUARDAN LAS CONVERSACIONES';
  @override
  String get archiveExplainer =>
      'Cada conversación se guarda al terminar cada turno, agrupada por '
      'proyecto: las de una carpeta van juntas y las de otra, aparte.';
  @override
  String get archiveNone => 'En ningún sitio';
  @override
  String get archiveFailedLocal =>
      'Esta conversación no se pudo guardar en el historial de Nexus. Sigue en '
      'pantalla: cópiala si te importa, porque al cerrarla se va.';
  @override
  String archiveFailedExternal(String destination) =>
      'No se pudo archivar en «$destination». La conversación está a salvo en el '
      'historial de Nexus, así que no se ha perdido nada.';
  @override
  String archiveFailedBoth(String destination) =>
      'Esta conversación no se pudo guardar ni en el historial de Nexus ni en '
      '«$destination». Sigue en pantalla: cópiala antes de cerrarla.';
  @override
  String get archiveNoneHint =>
      'Lo hablado vive solo mientras la conversación esté abierta';
  @override
  String get archiveFolder => 'Una carpeta tuya';
  @override
  String get archiveFolderHint =>
      'Markdown normal, legible en cualquier editor';
  @override
  String get archiveObsidian => 'Un vault de Obsidian';
  @override
  String get archiveObsidianHint =>
      'Lo mismo, con enlaces [[wiki]]: cada proyecto forma su propio grafo';
  @override
  String get archiveNotion => 'Notion';
  @override
  String get archiveNotionHint => 'Todavía no: falta conectar su API';
  @override
  String get archiveChooseFolder => 'ELEGIR CARPETA';
  @override
  String get archiveNoFolderYet =>
      'Falta elegir la carpeta: sin ella no se guarda nada, no se inventa un '
      'sitio donde dejar tus conversaciones.';
  @override
  String archiveLayout(String folder) =>
      'Se guardan en $folder/Nexus/<proyecto>/, con una nota por proyecto que '
      'enlaza sus conversaciones.';
  @override
  String get notionToken => 'TOKEN DE INTEGRACIÓN';
  @override
  String get notionTokenHint => 'Pega aquí tu token de Notion (ntn_…)';
  @override
  String get notionTokenExplainer =>
      'Se crea en notion.so/my-integrations y se guarda cifrado en este Mac, '
      'igual que la llave de Gemini. Nexus solo lo usa para escribir en la '
      'página que elijas.';
  @override
  String get notionPage => 'PÁGINA DONDE GUARDAR';
  @override
  String get notionPageHint => 'Pega la URL de la página de Notion';
  @override
  String get notionPageExplainer =>
      'Dentro se crea una página por proyecto, y dentro de cada una, sus '
      'conversaciones. Acuérdate de darle acceso a la integración desde el '
      'menú «…» de esa página, o Notion la esconderá.';
  @override
  String get notionReady => 'Conectado con Notion';
  @override
  String get notionMissing =>
      'Falta el token o la página: todavía no se guarda nada.';
  @override
  String get claudeAccount => 'Cuenta de Claude para esta carpeta';
  @override
  String get claudeAccountDefault => 'cuenta por defecto';
  @override
  String get deleteConversation => 'Borrar esta conversación';
  @override
  String get deleteForReal => 'BORRAR';
  @override
  String get cancel => 'CANCELAR';
  @override
  String claudeAccountSignedOut(String name) => '$name · sin sesión';

  @override
  String get beforeWeStart => 'ANTES DE EMPEZAR';
  @override
  String get setupTitle => 'Tres cosas antes de poder hablar contigo';

  @override
  String get readinessTitle => 'Falta algo para que Nexus pueda trabajar';

  @override
  String get tourOrbTitle => 'Háblale. Esto es Nexus';
  @override
  String get tourOrbBody =>
      'Pulsa el orbe y empieza a hablar. Se le pide en voz alta lo que quieres '
      'hacer en tu carpeta, y responde mientras Claude trabaja. El atajo global '
      'también lo despierta sin traer la ventana al frente.';
  @override
  String get tourComposerTitle => 'O escríbelo, si prefieres';
  @override
  String get tourComposerBody =>
      'Lo mismo por escrito, y aquí caen los archivos: arrastra una imagen o un '
      'documento y se adjunta a lo que pidas. Tocar la miniatura luego lo abre.';
  @override
  String get tourDockTitle => 'Tres conversaciones a la vez';
  @override
  String get tourDockBody =>
      'Cada una con su carpeta y su cuenta, trabajando en paralelo. Se cambia de '
      'una a otra sin perder lo que la otra estaba haciendo.';
  @override
  String get tourMeterTitle => 'Contexto y cupo, aquí dentro';
  @override
  String get sectionHelp => 'Ayuda';
  @override
  String get helpTourTitle => 'El tour de la primera vez';
  @override
  String get helpTourExplainer =>
      'Las cuatro piezas del HUD, señaladas una por una. Sale solo la primera vez; '
      'desde aquí se puede volver a ver.';
  @override
  String get helpTourAction => 'Ver el tour otra vez';
  @override
  String get versionLabel => 'Versión';
  @override
  String updateAvailable(String version) => 'Hay una versión nueva: $version';
  @override
  String get updateChecking => 'Buscando actualizaciones…';
  @override
  String get updateCheckNow => 'Buscar actualizaciones';
  @override
  String get updateUpToDate => 'Estás al día';
  @override
  String updateUpToDateBody(String version) =>
      'La $version es la última publicada.';
  @override
  String get updateFoundTitle => 'Hay una versión nueva';
  @override
  String updateWeight(String size) => 'La descarga pesa $size.';
  @override
  String updateDownloadedOf(String done, String total) => '$done de $total';
  @override
  String get updateLater => 'Más tarde';
  @override
  String get updateInstall => 'Actualizar';
  @override
  String get updateRestart => 'Reiniciar';
  @override
  String get updateDownloading => 'Descargando';
  @override
  String get updateExtracting => 'Preparando la actualización';
  @override
  String get updateReadyTitle => 'Lista para instalarse';
  @override
  String get updateReadyBody =>
      'Nexus se cerrará y volverá a abrirse. Si tienes un encargo en marcha, '
      'reiniciar lo corta a media escritura: espera a que termine.';
  @override
  String get updateInstalling => 'Instalando';
  @override
  String get updateInstallingBody =>
      'Nexus va a reiniciarse solo. No hace falta hacer nada.';
  @override
  String get updateFailedTitle => 'No se pudo actualizar';
  @override
  String get updateFailedBody => 'El actualizador no dijo por qué.';
  @override
  String get updateRetry => 'Volver a intentar';
  @override
  String get updateMoveTitle => 'Antes hay que moverla a Aplicaciones';
  @override
  String get updateMoveBody =>
      'Nexus está corriendo desde una copia de solo lectura que macOS monta '
      'para las apps que se abren sin instalarlas. Desde ahí no puede '
      'reemplazarse a sí misma. Arrástrala a Aplicaciones y vuelve a abrirla.';

  @override
  String get guideNeedsTitle => 'Qué necesita para funcionar';
  @override
  String get guideNeedsBody =>
      'Claude Code, instalado y con sesión. Es quien hace el trabajo de verdad: '
      'Nexus lanza su CLI en tu Mac y va con tu suscripción, no con una clave de '
      'API. Se comprueba al arrancar, y si falta te lo dice antes de dejarte '
      'entrar.\n\n'
      'Una llave de Gemini, que es la voz. Sin ella todo lo demás sigue '
      'funcionando por escrito.\n\n'
      'El micrófono, solo para hablarle.\n\n'
      'Y una carpeta emparejada: el trabajo pasa siempre dentro de una carpeta '
      'concreta, con su cuenta de Claude y sus permisos. Sin ninguna emparejada se '
      'trabaja en tu carpeta de documentos.';

  @override
  String get guidePrivacyTitle => 'Qué sale de tu Mac, y qué no';
  @override
  String get guidePrivacyBody =>
      'Cada carpeta se empareja en uno de dos modos, y arranca en el restrictivo: '
      '«solo texto», donde el servicio de voz no participa, o «voz», donde se '
      'puede abrir sesión hablada.\n\n'
      'Y aquí está lo que no es obvio: «solo texto» no significa «micrófono '
      'apagado». Aunque no hables, en cuanto Gemini narra un resultado, lo que '
      'Claude leyó de tu carpeta viaja hacia Google dentro de la respuesta de la '
      'herramienta. Restringir solo el micrófono dejaría la fuga abierta por el '
      'otro lado, así que en una carpeta de solo texto Gemini no participa: se '
      'escribe, Claude trabaja y la respuesta se lee.\n\n'
      'Tampoco significa que nada salga de tu Mac. Claude Code manda a Anthropic '
      'lo que lee de tu carpeta, porque es así como trabaja. Lo que este modo '
      'apaga es el servicio de voz, no el trabajo.\n\n'
      'Las demás carpetas emparejadas no viajan: cada conversación ve solo la '
      'suya. La única excepción es la carpeta de salida, que va en todos los '
      'encargos para poder guardar ahí lo que produzca — así que si la pones '
      'dentro de una carpeta de solo texto, la voz no se abre y se te dice cuál '
      'es.\n\n'
      'Aparte del modo, cada carpeta tiene permiso de archivos —solo leer o poder '
      'editar, y empieza en solo leer— y su propia lista de comandos bloqueados.';

  @override
  String get guidePiecesTitle => 'Las piezas que el tour no señala';
  @override
  String get guidePiecesBody =>
      'La columna de actividad aparece mientras hay trabajo: se ve lo que está '
      'haciendo paso a paso, y se puede parar con ⌘. o con el botón Detener.\n\n'
      'Los documentos que produce se abren en su propio visor, en una ventana '
      'aparte para poder mirarlos al lado de la conversación, y se recargan solos '
      'cuando cambian.\n\n'
      'Las skills, los plugins y los servidores MCP viven en la cuenta de Claude y '
      'no en el repo, así que valen en todas tus carpetas.\n\n'
      'Atajos: ⌥Espacio le habla sin traer la ventana al frente, ⌘Y abre el '
      'historial, ⌘, abre estos ajustes.';

  @override
  String get guideTroubleTitle => 'Cuando algo no va';
  @override
  String get guideTroubleBody =>
      '«Falta algo para que Nexus pueda trabajar» significa que no encuentra el '
      'binario de claude o que ninguna cuenta tiene sesión. Se arregla en una '
      'terminal, y luego «Comprobar de nuevo» no necesita reiniciar la app.\n\n'
      'Si no hay cifras de cupo, hay tres motivos distintos y el panel los '
      'diferencia: esa cuenta no ha iniciado sesión, la lectura del token caducó '
      '—que se arregla sola en cuanto vuelvas a usar la cuenta— o el servicio no '
      'contestó.\n\n'
      'Contexto y cupo no son lo mismo: puedes tener la ventana de contexto medio '
      'vacía y el cupo de la semana en las últimas.';
  @override
  String get tourMeterBody =>
      'Ábrelo y verás las dos cifras. El contexto es cuánta memoria lleva ocupada '
      'esta conversación; el cupo, cuánto queda de tu suscripción. Son dos cosas '
      'distintas: puedes tener la ventana medio vacía y el cupo en las últimas.';
  @override
  String get tourNext => 'Siguiente';
  @override
  String get tourDone => 'Entendido';
  @override
  String get tourSkip => 'Saltar el tour';
  @override
  String tourStep(int current, int total) => 'paso $current de $total';
  @override
  String get readinessExplainer =>
      'Nexus habla contigo, pero el trabajo lo hace Claude Code en tu Mac. '
      'Sin él no es que un encargo falle mal: es que falla sin decir por qué.';
  @override
  String get readinessCliMissing => 'Claude Code no está instalado';
  @override
  String get readinessCliMissingFix =>
      'Se instala una vez y Nexus lo encuentra solo. Si crees que ya lo tienes, '
      'comprueba en una terminal que «claude --version» conteste.';
  @override
  String get readinessSessionMissing => 'Ninguna cuenta tiene sesión abierta';
  @override
  String get readinessSessionMissingFix =>
      'Abre una terminal, escribe «claude» y completa el inicio de sesión. '
      'Nexus trabaja con tu suscripción, no con una clave de API.';
  @override
  String get readinessHowToInstall => 'Cómo se instala';
  @override
  String get readinessRecheck => 'Comprobar de nuevo';
  @override
  String get readinessContinueAnyway => 'Entrar de todas formas';
  @override
  String get readinessContinueHint =>
      'Puedes entrar y arreglarlo luego: los ajustes y el historial funcionan igual.';
  @override
  String get setupExplainer =>
      'Nexus necesita tu micrófono para escucharte, una llave de Gemini para '
      'darte voz y una carpeta donde trabajar. Nada de esto se comparte con '
      'nadie más.';
  @override
  String get startUsingNexus => 'EMPEZAR A USAR NEXUS';
  @override
  String get changeLaterHint => 'Puedes cambiar esto después en Ajustes';
  @override
  String get request => 'SOLICITAR';
  @override
  String get micPending => 'PENDIENTE';
  @override
  String get micPendingExplainer =>
      'Vas a ver el diálogo de permiso de macOS. En cuanto lo aceptes, la '
      'prueba de sonido en vivo empieza sola.';
  @override
  String get micAsking => 'Pidiendo acceso al micrófono…';
  @override
  String get micAskingExplainer =>
      'Responde al diálogo del sistema para continuar.';
  @override
  String get micGranted => 'CONCEDIDO';
  @override
  String get micGrantedExplainer =>
      'Habla un momento — si el trazo se mueve, tu voz llega bien a Nexus.';
  @override
  String get micDenied => 'DENEGADO';
  @override
  String get microphoneBlocked =>
      'El micrófono está bloqueado, así que no se puede abrir la voz. Se concede '
      'en Ajustes del sistema › Privacidad y seguridad › Micrófono, marcando '
      'Nexus. Mientras tanto, puedes escribirle por abajo.';
  @override
  String get micDeniedShort => 'Actívalo en Ajustes del Sistema';
  @override
  String get micDeniedExplainer =>
      'Nexus no puede escucharte todavía. Actívalo en Ajustes del Sistema › '
      'Privacidad y seguridad › Micrófono.';
  @override
  String get microphone => 'MICRÓFONO';
  @override
  String get iHearYou => 'TE ESCUCHO';
  @override
  String get workFolder => 'CARPETA DE TRABAJO';
  @override
  String get choose => 'ELEGIR';
  @override
  String get chosen => 'ELEGIDA';
  @override
  String get workFolderTitle => 'Nexus solo trabaja donde le digas';
  @override
  String get workFolderExplainer =>
      'Puede ser un proyecto o la carpeta que los contiene a todos. Si las '
      'reglas de un repo viven fuera de él, elige la carpeta padre. Después '
      'puedes añadir más en Ajustes.';
  @override
  String get geminiKey => 'LLAVE DE VOZ (GEMINI)';
  @override
  String get geminiKeyHint => 'Pega tu llave de API aquí';
  @override
  String get geminiKeyExplainer =>
      'Se guarda cifrada en este Mac. Solo viaja hacia Google para sostener la '
      'voz en tiempo real.';
  @override
  String get getFreeKey => 'CONSEGUIR UNA LLAVE GRATIS ↗';
  @override
  String keySaveFailed(String error) => 'No se pudo guardar la llave: $error';
}

class NexusStringsEn extends NexusStrings {
  const NexusStringsEn();

  @override
  String get languageName => 'English';

  @override
  String get brand => 'N E X U S';
  @override
  String get starting => 'STARTING';
  @override
  String get asleep => 'Asleep';
  @override
  String get listening => 'Listening';
  @override
  String get working => 'Working';
  @override
  String get speaking => 'Speaking';

  @override
  String get pairFolder => 'PAIR A FOLDER';
  @override
  String get noConversation => 'no conversation';
  @override
  String get textOnly => 'TEXT ONLY';
  @override
  String get readOnly => 'READ ONLY';
  @override
  String get canEdit => 'CAN EDIT';
  @override
  String get canEditExplainer => 'Changes files without asking';
  @override
  String get readOnlyExplainer => 'Reads and runs, but never writes';
  @override
  String contextUsed(int percent) =>
      'Context used: $percent%. At 85% the conversation compacts itself.';
  @override
  String get attachFile => 'Attach a file';
  @override
  String get orbLabel => 'Nexus orb';
  @override
  String get orbHint => 'Activate to talk to it. It also answers to ⌥Space.';
  @override
  String get sectionStats => 'Statistics';
  @override
  String get statsOverview => 'Overview';
  @override
  String get statsModels => 'Models';
  @override
  String get statsRangeAll => 'All';
  @override
  String get statsRange30 => '30d';
  @override
  String get statsRange7 => '7d';
  @override
  String get statsSessions => 'Sessions';
  @override
  String get statsMessages => 'Messages';
  @override
  String get statsTotalTokens => 'Tokens';
  @override
  String get statsActiveDays => 'Active days';
  @override
  String get statsCurrentStreak => 'Current streak';
  @override
  String get statsLongestStreak => 'Longest streak';
  @override
  String get statsPeakHour => 'Peak hour';
  @override
  String get statsFavoriteModel => 'Favorite model';
  @override
  String get statsReading => 'Reading the transcripts…';
  @override
  String get statsUnreadable =>
      'This account\'s transcripts could not be read.';
  @override
  String get statsNothingYet => 'Nothing to count in this range yet.';
  @override
  String get statsNoAccounts => 'No Claude account is set up.';
  @override
  String statsCachedFootnote(String amount) =>
      'Plus $amount tokens read from or written to cache — kept out of the '
      'total because it would dwarf it.';
  @override
  String statsDayTooltip(String day, int messages) =>
      '$day · $messages messages';
  @override
  String statsInOut(String input, String output) => '$input in · $output out';
  @override
  String get sectionSuperpowers => 'Superpowers';
  @override
  String get sectionAppearance => 'Appearance';
  @override
  String get themeTitle => 'Light or dark';
  @override
  String get accentTitle => 'Accent colour';
  @override
  String get accentExplainer =>
      'The tone of the orb and of everything that stands out. You pick the '
      'colour; the app adjusts the brightness so it reads in both themes.';
  @override
  String get accentPick => 'Pick the colour';
  @override
  String get accentAdjusted =>
      'The brightness is adjusted, not the colour: over the void a lighter tone '
      'is needed, and over a light background a darker one. Your hue is kept.';
  @override
  String get accentReset => 'Back to the original';
  @override
  String get accentInDark => 'In dark';
  @override
  String get accentInLight => 'In light';
  @override
  String get accentNameRed => 'Red';
  @override
  String get accentNameOrange => 'Orange';
  @override
  String get accentNameAmber => 'Amber';
  @override
  String get accentNameLime => 'Lime';
  @override
  String get accentNameGreen => 'Green';
  @override
  String get accentNameEmerald => 'Emerald';
  @override
  String get accentNameCyan => 'Cyan';
  @override
  String get accentNameBlue => 'Blue';
  @override
  String get accentNameIndigo => 'Indigo';
  @override
  String get accentNameViolet => 'Violet';
  @override
  String get accentNameMagenta => 'Magenta';
  @override
  String get accentNameRose => 'Rose';
  @override
  String get accentNameGrey => 'Grey';
  @override
  String get themeExplainer =>
      'The app is born dark because it is a HUD, and at night that is welcome. '
      'In broad daylight a black background reads worse, though, and nobody is '
      'going to switch the whole Mac for that: pick it here instead.';
  @override
  String get themeSystem => "The system's";
  @override
  String get themeLight => 'Light';
  @override
  String get themeDark => 'Dark';
  @override
  String get mcpExplainer =>
      'An MCP server gives Claude hands beyond the disk: a browser, a '
      "library's documentation, your Jira. They are set per account.";
  @override
  String get mcpInstalled => 'Set up in this account';
  @override
  String get mcpNone => 'None yet.';
  @override
  String get mcpCatalog => 'One click away';
  @override
  String get mcpManual => 'Another one, by hand';
  @override
  String get mcpNameHint => 'name';
  @override
  String get mcpSpecHint => 'https://… or the command that starts it';
  @override
  String get mcpAdd => 'Add';
  @override
  String get mcpRemove => 'Remove';
  @override
  String get mcpCheck => 'Check';
  @override
  String get mcpCheckNote =>
      'Asks every server whether it answers. Slow, and it also brings in your '
      'claude.ai account connectors.';
  @override
  String get mcpChecking => 'Asking each one…';
  @override
  String get mcpCheckFailed => 'The CLI could not produce the list.';
  @override
  String get superpowersMcp => 'MCP servers';

  @override
  String get superpowersEverywhere => 'In every account';

  @override
  String get superpowersOnlyHere =>
      'What you install here is only visible to this account\'s folders — including '
      'their errands, which run with their folder\'s account.';
  @override
  String get superpowersSkills => 'Skills';
  @override
  String get skillsExplainer =>
      'A skill is a written procedure the agent activates on its own when the '
      'task calls for it. Installed on the account any project can use it; '
      'written inside a repo, only that one.';
  @override
  String get skillsInstalled => 'Installed on this account';
  @override
  String get skillsNone => 'None yet.';
  @override
  String get skillsFromRepo => 'Bring some from a repository';
  @override
  String get skillsSearchHint => "search the repo's";
  @override
  String skillsCatalog(int total) => 'What the repo brings ($total)';
  @override
  String skillsMore(int rest) => 'And $rest more. Search to see them.';
  @override
  String get skillsBrowse => 'See what it has';
  @override
  String get skillsInstall => 'Install';
  @override
  String get skillsUpdate => 'Update';
  @override
  String get skillsRemove => 'Remove';
  @override
  String get skillsFetching => 'Fetching the repository…';
  @override
  String get skillsRepoFailed => 'That repository could not be read.';
  @override
  String get skillsOwn => 'Write your own';
  @override
  String get skillsOwnHint => 'what it is called';
  @override
  String get skillsCreate => 'Create and open';
  @override
  String get superpowersPlugins => 'Plugins';
  @override
  String get pluginsExplainer =>
      'A plugin ships skills, agents and commands together. They come from the '
      'marketplaces you have registered.';
  @override
  String get pluginsInstalled => 'Installed on this account';
  @override
  String get pluginsNone => 'None yet.';
  @override
  String get pluginsLoading => 'Asking the CLI…';
  @override
  String get pluginsMarketplaces => 'Marketplaces';
  @override
  String get pluginsMarketplaceHint => 'user/repo, or a URL';
  @override
  String get pluginsAddMarketplace => 'Register';
  @override
  String get pluginsRemoveMarketplace => 'Remove the marketplace';
  @override
  String get pluginsSearchHint => 'search the available ones';
  @override
  String get pluginsInstall => 'Install';
  @override
  String get pluginsUninstall => 'Uninstall';
  @override
  String get pluginsEnable => 'Turn on';
  @override
  String get pluginsDisable => 'Turn off without uninstalling';
  @override
  String get pluginsUpdate => 'Update';
  @override
  String get pluginsDetails => 'What it brings and how much context it costs';
  @override
  String get pluginsNoDetails => 'The CLI gave no details for this plugin.';
  @override
  String get close => 'Close';
  @override
  String pluginsCatalog(int total) => 'Available ($total)';
  @override
  String pluginsMore(int rest) => 'And $rest more. Search to see them.';
  @override
  String get artifacts => 'Documents';
  @override
  String get noProject => 'No project';
  @override
  String get artifactsExplainer =>
      "The folder for whatever isn't part of a project: conversations with no "
      'project work there, and Claude leaves what it produces there.';
  @override
  String get artifactsNoFolder =>
      "Pick a folder for whatever isn't part of a project. Conversations with "
      'no project will work there, and Claude will leave what it makes there.';
  @override
  String get artifactsEmpty => 'Nothing in that folder yet.';
  @override
  String get artifactsChoose => 'Pick a folder';
  @override
  String get artifactsChange => 'Change folder';
  @override
  String get artifactsReveal => 'Show in Finder';
  @override
  String get artifactsTrash => 'Move to trash';
  @override
  String get dropHere => 'Drop it here';
  @override
  String get attachedFilesLabel => 'Attached files:';
  @override
  String get chooseFolder => 'Choose folder';
  @override
  String get noGitRepo => 'no git';
  @override
  String changedFiles(int count) => count == 1
      ? 'SEE THE FILE IT TOUCHED'
      : 'SEE THE $count FILES IT TOUCHED';
  @override
  String get changesTitle => 'WHAT THIS TASK CHANGED';
  @override
  String get newFile => 'new';
  @override
  String blockedTitle(String folder) => 'COMMANDS BLOCKED IN $folder';
  @override
  String get blockedExplainer =>
      'One per line, and a fragment of the command is enough. Not a plea: the '
      'CLI denies them, so there is no way around it. Claude will do everything '
      'else and finish by telling you the exact command to run. # comments.';
  @override
  String get blockedHint => 'build_runner\npod install\nmake generate';
  @override
  String get addFolderShort => 'Pair another folder';
  @override
  String get openSettings => 'Settings…';
  @override
  String get statusTalk => 'Talk to Nexus';
  @override
  String get statusShow => 'Open the window';
  @override
  String get statusQuit => 'Quit Nexus';
  @override
  String get errandDone => 'The errand is done.';
  @override
  String get errandFailed => 'The errand could not be finished.';
  @override
  String get modelTitle => 'Model';
  @override
  String get effortTitle => 'Effort';
  @override
  String get effortFaster => 'Faster';
  @override
  String get effortSmarter => 'Smarter';
  @override
  String get contextWindow => 'Context window';
  @override
  String get usageLimits => 'Your subscription limits';
  @override
  String get usageFiveHour => '5-hour limit';
  @override
  String get usageWeekly => 'Weekly';
  @override
  String get usageUnavailable =>
      'No reading: that account has no session open.';
  @override
  String get usageStale =>
      'No reading for now: the session is still open, but its access expired. '
      'It comes back as soon as you use this account.';
  @override
  String get usageUnreachable =>
      'No reading: the quota could not be asked for.';
  @override
  String get noReadingYet => 'No reading';
  @override
  String resetsIn(String when) => 'Resets $when';
  @override
  String get sayStopToInterrupt => 'Say “stop” to interrupt';
  @override
  String get stopWithShortcut => 'Stop with ⌘.';
  @override
  String get workingCancelHint => 'WORKING · ⌥SPACE TO CANCEL';
  @override
  String get micOpenHint => 'MICROPHONE OPEN · CLOSES ITSELF WHEN YOU STOP';
  @override
  String get noFolderNothingToTouch =>
      'No folder paired — nothing to touch yet';
  @override
  String canEditFilesIn(String folder) => 'Can edit files in $folder';
  @override
  String readOnlyIn(String folder) => 'Read only in $folder';

  @override
  String get openAnotherConversation => 'Open another conversation';
  @override
  String get newConversation => 'NEW';
  @override
  String get pairAFolderToStart => 'PAIR A FOLDER TO START';
  @override
  String get askSomething =>
      'ASK FOR SOMETHING — BY VOICE WITH ⌥SPACE OR TYPING BELOW';
  @override
  String get you => 'YOU';
  @override
  String get nexus => 'NEXUS';

  @override
  String get composerHint => 'Type an instruction…   ⇧↵ for a new line';
  @override
  String get clearWhatYouWrote => 'Clear what you wrote';

  @override
  String get rightNow => 'RIGHT NOW';
  @override
  String get noStepsYet =>
      'Thinking. Steps show up here as soon as it touches something — some errands are answered without opening anything.';
  @override
  String get stopButton => 'STOP  ⌘.';
  @override
  String get writesTag => 'WRITES';
  @override
  String get ranLabel => 'IT RAN';
  @override
  String get returnedLabel => 'IT RETURNED';
  @override
  String get stillRunning => 'still running…';
  @override
  String get waitingForOtherConversation =>
      'Waiting for the other conversation on this folder';
  @override
  String get waitingByVoice =>
      'I am waiting my turn: another conversation is working on that folder.';
  @override
  String get noFolderForConversation =>
      'This conversation has no folder paired: there is nowhere to work.';
  @override
  String textOnlyFolder(String folder) =>
      'The folder $folder is in text-only mode, so the microphone stays shut. '
      'Type below, or change the mode in Settings.';

  @override
  String textOnlyArtifactsFolder(String folder) =>
      'The output folder "$folder" is text only, and it travels with every '
      'errand: whatever is kept there could end up narrated. Voice will not open '
      'until you change it or give it voice mode.';
  @override
  String compacting(int percent) =>
      'Context at $percent%: compacting the conversation so it can go on '
      'without losing the thread';
  @override
  String get compactedUnknown =>
      'Conversation compacted. The context reading updates on the next turn.';
  @override
  String compacted(int before, int after) =>
      'Conversation compacted: context drops from $before% to $after%. Claude '
      'keeps a summary of what was said.';

  @override
  String get history => 'HISTORY';
  @override
  String get historyExplainer =>
      'From this folder, and it survives restarts. Claude resumes the previous '
      'conversation, so it knows what you already did together.';
  @override
  String get nothingAskedYet => 'You have not asked for anything yet.';
  @override
  String startFromScratchIn(String folder) =>
      'MAKE CLAUDE FORGET WHAT WAS SAID IN $folder';
  @override
  String get conversationForgotten =>
      'Conversation forgotten: the next one starts from scratch.';

  @override
  String get settings => 'SETTINGS';
  @override
  String get closeEsc => 'CLOSE  ESC';
  @override
  String get sectionVoice => 'Voice';
  @override
  String get sectionPermissions => 'Permissions';
  @override
  String get sectionLanguage => 'Language';
  @override
  String get sectionMobile => 'Mobile';
  @override
  String get channelTitle => 'The phone channel';
  @override
  String get channelExplainer =>
      'It listens over Tailscale only, never on the local network. That way '
      'WireGuard already provides the encryption and the identity, and no '
      'certificates are needed.';
  @override
  String get channelSwitch => 'Accept connections from the phone';
  @override
  String get channelStarting => 'Opening the channel…';
  @override
  String get channelListeningAt => 'Listening on';
  @override
  String get channelToken => 'Token';
  @override
  String get channelCopyToken => 'Copy';
  @override
  String get channelRotateToken => 'Rotate';
  @override
  String get channelRotateWarning =>
      'Rotating it closes open connections and locks every phone out: that is how '
      'access is revoked.';
  @override
  String get channelNeedsTailscale =>
      'I cannot find Tailscale on this Mac. The channel only listens there, so it '
      'has to be installed and signed in — on the Mac and on the phone.';
  @override
  String get channelPortBusy =>
      'Port 7845 is taken. Almost always another copy of Nexus is open: close it '
      'and turn this on again.';
  @override
  String get channelUnknownProblem =>
      'The channel could not open. The reason is in the system log.';
  @override
  @override
  String get channelQrExplainer =>
      'Scan it from the phone app. It carries this address and this token, so it is '
      'the same as typing them — only without typing 43 characters.';
  @override
  String get channelNoPhoneYet =>
      'The phone app exists now: it installs from the repository, pairs by pasting '
      'the address and token from here, and needs Tailscale on the phone just as it '
      'does here. What there is no yet is a published mobile release.';
  @override
  String get phraseTitle => 'Write phrase';
  @override
  String get phraseExplainer =>
      'The token lets the phone in; this phrase is what lets it write. It is never '
      'stored on the phone: it is typed when needed and checked by this Mac, so '
      'taking the phone is not enough to write.';
  @override
  String get phraseDefined => 'Defined';
  @override
  String get phraseMissing =>
      'Not set: the phone can ask and read, but not write.';
  @override
  String get phraseDefine => 'Set';
  @override
  String get phraseChange => 'Change';
  @override
  String get phraseRemove => 'Remove';
  @override
  String get phraseTooShort => 'At least eight characters.';
  @override
  String get phraseSave => 'Save';
  @override
  String get phraseChangeWarning =>
      'Changing or removing it closes any write permission already open.';
  @override
  String get sectionModel => 'Model';
  @override
  String get nexusVoice => 'NEXUS VOICE';
  @override
  String get audioOutput => 'WHERE IT PLAYS';
  @override
  String get audioOutputExplainer =>
      'Applies the next time you talk to it: the device is fixed when the audio '
      'is set up. On «system», switching headphones switches this too.';
  @override
  String get audioOutputSystem => 'Whatever the system uses';
  @override
  String get voiceExplainer =>
      'It is fixed when the session opens, so a change applies the next time '
      'you talk to it.';
  @override
  String get filePermissionsTitle => 'PERMISSIONS OVER YOUR FILES';
  @override
  String get filePermissionsExplainer =>
      'This switch is always visible in the top bar. On “read only”, Nexus can '
      'open files and run commands that do not write; on “can edit”, it changes '
      'files too.';
  @override
  String get foldersWithPermission => 'FOLDERS WITH PERMISSION';
  @override
  String get noFoldersYet =>
      'None yet. With no folder paired there is nowhere to work: Claude would '
      'run on the root of the disk.';
  @override
  String get addFolder => 'ADD FOLDER';
  @override
  String get foldersExplainer =>
      'Each conversation works on one folder and **only** that one: it is the '
      'context boundary. If a repo keeps its rules outside itself — an '
      'ai-context next to it — pair the parent folder rather than both.';
  @override
  String get isActiveFolder => 'This is the active folder';
  @override
  String get workHere => 'Work here';
  @override
  String get remove => 'Remove';
  @override
  String get voiceAllowedExplainer =>
      'You can talk to this folder: your voice and whatever Claude reads go out '
      'to Google';
  @override
  String get textOnlyExplainer =>
      'Text only: nothing from this folder goes to the voice service';
  @override
  String get languageTitle => 'LANGUAGE';
  @override
  String get languageExplainer =>
      'Changes the interface and also how you are answered: the voice and '
      'Claude reply in the chosen language.';
  @override
  String get languageSystem => 'Follow the system';
  @override
  String get languageSpanish => 'Español';
  @override
  String get languageEnglish => 'English';

  @override
  String get sectionHistory => 'History';
  @override
  String get archiveTitle => 'WHERE CONVERSATIONS ARE KEPT';
  @override
  String get archiveExplainer =>
      'Each conversation is saved as every turn ends, grouped by project: the '
      'ones from a folder stay together, and another folder\'s stay apart.';
  @override
  String get archiveNone => 'Nowhere';
  @override
  String get archiveFailedLocal =>
      'This conversation could not be saved to the Nexus history. It is still on '
      'screen: copy it if it matters, because closing it loses it.';
  @override
  String archiveFailedExternal(String destination) =>
      'It could not be archived to "$destination". The conversation is safe in the '
      'Nexus history, so nothing was lost.';
  @override
  String archiveFailedBoth(String destination) =>
      'This conversation could not be saved to the Nexus history or to '
      '"$destination". It is still on screen: copy it before closing.';
  @override
  String get archiveNoneHint =>
      'What is said lives only while the conversation is open';
  @override
  String get archiveFolder => 'A folder of yours';
  @override
  String get archiveFolderHint => 'Plain Markdown, readable in any editor';
  @override
  String get archiveObsidian => 'An Obsidian vault';
  @override
  String get archiveObsidianHint =>
      'The same, with [[wiki]] links: each project forms its own graph';
  @override
  String get archiveNotion => 'Notion';
  @override
  String get archiveNotionHint => 'Not yet: its API is still to be wired';
  @override
  String get archiveChooseFolder => 'CHOOSE FOLDER';
  @override
  String get archiveNoFolderYet =>
      'A folder is still missing: without one nothing is saved — no place to '
      'leave your conversations gets invented for you.';
  @override
  String archiveLayout(String folder) =>
      'Kept in $folder/Nexus/<project>/, with one note per project linking its '
      'conversations.';
  @override
  String get notionToken => 'INTEGRATION TOKEN';
  @override
  String get notionTokenHint => 'Paste your Notion token here (ntn_…)';
  @override
  String get notionTokenExplainer =>
      'Created at notion.so/my-integrations and stored encrypted on this Mac, '
      'like the Gemini key. Nexus only uses it to write in the page you pick.';
  @override
  String get notionPage => 'PAGE TO SAVE INTO';
  @override
  String get notionPageHint => 'Paste the Notion page URL';
  @override
  String get notionPageExplainer =>
      'One page per project is created inside it, and each holds its own '
      'conversations. Remember to share the page with your integration from '
      'its «…» menu, or Notion will keep it hidden.';
  @override
  String get notionReady => 'Connected to Notion';
  @override
  String get notionMissing =>
      'Token or page missing: nothing is being saved yet.';
  @override
  String get claudeAccount => 'Claude account for this folder';
  @override
  String get claudeAccountDefault => 'default account';
  @override
  String get deleteConversation => 'Delete this conversation';
  @override
  String get deleteForReal => 'DELETE';
  @override
  String get cancel => 'CANCEL';
  @override
  String claudeAccountSignedOut(String name) => '$name · not signed in';

  @override
  String get beforeWeStart => 'BEFORE WE START';
  @override
  String get setupTitle => 'Three things before it can talk to you';

  @override
  String get readinessTitle => 'Something is missing before Nexus can work';

  @override
  String get tourOrbTitle => 'Talk to it. This is Nexus';
  @override
  String get tourOrbBody =>
      'Press the orb and start talking. You ask out loud for what you want done '
      'in your folder, and it answers while Claude works. The global shortcut '
      'also wakes it without bringing the window to the front.';
  @override
  String get tourComposerTitle => 'Or type it, if you prefer';
  @override
  String get tourComposerBody =>
      'The same thing in writing, and this is where files land: drag an image or '
      'a document and it is attached to what you ask. Tapping the thumbnail later '
      'opens it.';
  @override
  String get tourDockTitle => 'Three conversations at once';
  @override
  String get tourDockBody =>
      'Each with its own folder and account, working in parallel. You switch '
      'between them without losing what the other one was doing.';
  @override
  String get tourMeterTitle => 'Context and quota, in here';
  @override
  String get sectionHelp => 'Help';
  @override
  String get helpTourTitle => 'The first-run tour';
  @override
  String get helpTourExplainer =>
      'The four pieces of the HUD, pointed at one by one. It only shows the first '
      'time; from here you can see it again.';
  @override
  String get helpTourAction => 'See the tour again';
  @override
  String get versionLabel => 'Version';
  @override
  String updateAvailable(String version) => 'There is a new version: $version';
  @override
  String get updateChecking => 'Checking for updates…';
  @override
  String get updateCheckNow => 'Check for updates';
  @override
  String get updateUpToDate => 'You are up to date';
  @override
  String updateUpToDateBody(String version) =>
      'Version $version is the latest published.';
  @override
  String get updateFoundTitle => 'There is a new version';
  @override
  String updateWeight(String size) => 'The download is $size.';
  @override
  String updateDownloadedOf(String done, String total) => '$done of $total';
  @override
  String get updateLater => 'Later';
  @override
  String get updateInstall => 'Update';
  @override
  String get updateRestart => 'Restart';
  @override
  String get updateDownloading => 'Downloading';
  @override
  String get updateExtracting => 'Preparing the update';
  @override
  String get updateReadyTitle => 'Ready to install';
  @override
  String get updateReadyBody =>
      'Nexus will quit and open again. If an errand is running, restarting '
      'cuts it mid-write: wait until it finishes.';
  @override
  String get updateInstalling => 'Installing';
  @override
  String get updateInstallingBody =>
      'Nexus will restart on its own. Nothing to do.';
  @override
  String get updateFailedTitle => 'Could not update';
  @override
  String get updateFailedBody => 'The updater did not say why.';
  @override
  String get updateRetry => 'Try again';
  @override
  String get updateMoveTitle => 'It has to be moved to Applications first';
  @override
  String get updateMoveBody =>
      'Nexus is running from the read-only copy macOS mounts for apps opened '
      'without installing them. From there it cannot replace itself. Drag it '
      'to Applications and open it again.';

  @override
  String get guideNeedsTitle => 'What it needs to work';
  @override
  String get guideNeedsBody =>
      'Claude Code, installed and signed in. It is what actually does the work: '
      'Nexus launches its CLI on your Mac and runs on your subscription, not on an '
      'API key. It is checked at startup, and if it is missing you are told before '
      'you get in.\n\n'
      'A Gemini key, which is the voice. Without it everything else still works in '
      'writing.\n\n'
      'The microphone, only for talking to it.\n\n'
      'And a paired folder: work always happens inside a specific folder, with its '
      'own Claude account and permissions. With none paired, it works in your '
      'documents folder.';

  @override
  String get guidePrivacyTitle => 'What leaves your Mac, and what does not';
  @override
  String get guidePrivacyBody =>
      'Each folder is paired in one of two modes, and starts in the restrictive '
      'one: "text only", where the voice service takes no part, or "voice", where a '
      'spoken session can be opened.\n\n'
      'And here is the part that is not obvious: "text only" does not mean '
      '"microphone off". Even if you never speak, the moment Gemini narrates a '
      'result, whatever Claude read from your folder travels to Google inside the '
      'tool response. Restricting only the microphone would leave the leak open on '
      'the other side, so in a text-only folder Gemini takes no part: you type, '
      'Claude works, and you read the answer.\n\n'
      'It does not mean nothing leaves your Mac either. Claude Code sends what it '
      'reads from your folder to Anthropic, because that is how it works. What this '
      'mode turns off is the voice service, not the work.\n\n'
      'The other paired folders do not travel: each conversation sees only its own. '
      'The one exception is the output folder, which goes with every errand so that '
      'whatever is produced can be kept there — so if you put it inside a text-only '
      'folder, voice will not open, and you are told which one.\n\n'
      'Besides the mode, each folder has a file permission — read only or can edit, '
      'starting at read only — and its own list of blocked commands.';

  @override
  String get guidePiecesTitle => 'The pieces the tour does not point at';
  @override
  String get guidePiecesBody =>
      'The activity column shows up while there is work: you see what it is doing '
      'step by step, and you can stop it with ⌘. or the Stop button.\n\n'
      'The documents it produces open in their own viewer, in a separate window so '
      'you can look at them next to the conversation, and they reload themselves '
      'when they change.\n\n'
      'Skills, plugins and MCP servers live in the Claude account rather than in '
      'the repo, so they apply across all your folders.\n\n'
      'Shortcuts: ⌥Space talks to it without bringing the window to the front, ⌘Y '
      'opens the history, ⌘, opens these settings.';

  @override
  String get guideTroubleTitle => 'When something does not work';
  @override
  String get guideTroubleBody =>
      '"Something is missing before Nexus can work" means it cannot find the claude '
      'binary, or no account is signed in. You fix it in a terminal, and then '
      '"Check again" does not need an app restart.\n\n'
      'If there are no quota figures, there are three different reasons and the '
      'panel tells them apart: that account has not signed in, the token reading '
      'expired — which fixes itself as soon as you use the account again — or the '
      'service did not answer.\n\n'
      'Context and quota are not the same thing: you can have the context window '
      'half empty and the weekly quota nearly gone.';
  @override
  String get tourMeterBody =>
      'Open it and you will see both figures. Context is how much memory this '
      'conversation is using; quota is how much of your subscription is left. They '
      'are different things: you can have the window half empty and the quota gone.';
  @override
  String get tourNext => 'Next';
  @override
  String get tourDone => 'Got it';
  @override
  String get tourSkip => 'Skip the tour';
  @override
  String tourStep(int current, int total) => 'step $current of $total';
  @override
  String get readinessExplainer =>
      'Nexus does the talking, but the work is done by Claude Code on your Mac. '
      'Without it an errand does not fail badly — it fails without saying why.';
  @override
  String get readinessCliMissing => 'Claude Code is not installed';
  @override
  String get readinessCliMissingFix =>
      'Install it once and Nexus finds it on its own. If you think you already '
      'have it, check that «claude --version» answers in a terminal.';
  @override
  String get readinessSessionMissing => 'No account is signed in';
  @override
  String get readinessSessionMissingFix =>
      'Open a terminal, type «claude» and complete the sign-in. Nexus works '
      'with your subscription, not with an API key.';
  @override
  String get readinessHowToInstall => 'How to install it';
  @override
  String get readinessRecheck => 'Check again';
  @override
  String get readinessContinueAnyway => 'Go in anyway';
  @override
  String get readinessContinueHint =>
      'You can go in and fix it later: settings and history work the same.';
  @override
  String get setupExplainer =>
      'Nexus needs your microphone to hear you, a Gemini key to give you a '
      'voice, and a folder to work in. None of it is shared with anyone else.';
  @override
  String get startUsingNexus => 'START USING NEXUS';
  @override
  String get changeLaterHint => 'You can change this later in Settings';
  @override
  String get request => 'REQUEST';
  @override
  String get micPending => 'PENDING';
  @override
  String get micPendingExplainer =>
      'You will see the macOS permission dialog. As soon as you accept it, the '
      'live sound test starts on its own.';
  @override
  String get micAsking => 'Asking for microphone access…';
  @override
  String get micAskingExplainer => 'Answer the system dialog to continue.';
  @override
  String get micGranted => 'GRANTED';
  @override
  String get micGrantedExplainer =>
      'Say something — if the trace moves, your voice is reaching Nexus.';
  @override
  String get micDenied => 'DENIED';
  @override
  String get microphoneBlocked =>
      'The microphone is blocked, so voice cannot start. You grant it in System '
      'Settings › Privacy & Security › Microphone, ticking Nexus. In the '
      'meantime you can type to it below.';
  @override
  String get micDeniedShort => 'Turn it on in System Settings';
  @override
  String get micDeniedExplainer =>
      'Nexus cannot hear you yet. Turn it on in System Settings › Privacy & '
      'Security › Microphone.';
  @override
  String get microphone => 'MICROPHONE';
  @override
  String get iHearYou => 'I HEAR YOU';
  @override
  String get workFolder => 'WORK FOLDER';
  @override
  String get choose => 'CHOOSE';
  @override
  String get chosen => 'CHOSEN';
  @override
  String get workFolderTitle => 'Nexus only works where you tell it to';
  @override
  String get workFolderExplainer =>
      'It can be one project or the folder holding all of them. If a repo keeps '
      'its rules outside itself, pick the parent folder. You can add more later '
      'in Settings.';
  @override
  String get geminiKey => 'VOICE KEY (GEMINI)';
  @override
  String get geminiKeyHint => 'Paste your API key here';
  @override
  String get geminiKeyExplainer =>
      'Stored encrypted on this Mac. It only travels to Google to keep the '
      'real-time voice going.';
  @override
  String get getFreeKey => 'GET A FREE KEY ↗';
  @override
  String keySaveFailed(String error) => 'Could not save the key: $error';
}

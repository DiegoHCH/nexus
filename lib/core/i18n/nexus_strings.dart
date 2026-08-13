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
  String get superpowersSkills;
  String get skillsExplainer;
  String get skillsInstalled;
  String get skillsNone;
  String get skillsFromRepo;
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
  String get modelTitle;
  String get effortTitle;
  String get effortFaster;
  String get effortSmarter;
  String get contextWindow;
  String get usageLimits;
  String get usageFiveHour;
  String get usageWeekly;
  String get usageUnavailable;
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
  String get stopButton;
  String get writesTag;
  String get ranLabel;
  String get returnedLabel;
  String get stillRunning;
  String get waitingForOtherConversation;
  String get waitingByVoice;
  String get noFolderForConversation;
  String textOnlyFolder(String folder);
  String compacting(int percent);
  String compacted(int before, int after);

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
      'Sin dato: esa cuenta no tiene sesión abierta o el acceso caducó.';
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
  String compacting(int percent) =>
      'Contexto al $percent %: comprimiendo la conversación para seguir sin '
      'perder el hilo';
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
      'No reading: that account has no session open, or its access expired.';
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
  String compacting(int percent) =>
      'Context at $percent%: compacting the conversation so it can go on '
      'without losing the thread';
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

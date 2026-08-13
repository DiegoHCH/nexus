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

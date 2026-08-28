/// El arranque y el tour.
///
/// La configuración inicial, la comprobación de que todo está, y las
/// cuatro paradas de la primera vez.
///
/// Los tres van juntos —lo que se declara y sus dos traducciones— porque lo
/// que se rompe es la terna: añadir un texto y olvidar un idioma. Tenerlos en
/// el mismo archivo hace que el hueco se vea al escribirlo, no al compilar.
mixin ArranqueStrings {
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
  String get guideNotForTitle;
  String get guideNotForBody;
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
  String get hayMasAbajo;
  String get request;
  String get micPending;
  String get micPendingExplainer;
  String get micAsking;
  String get micAskingExplainer;
  String get micGranted;
  String get micGrantedExplainer;
  String get micDenied;
  String get microphoneBlocked;

  /// Las reglas del repositorio no son las mismas que la última vez. Lleva las
  /// rutas porque cuál cambió es el dato: uno del proyecto y uno de tres
  /// carpetas más arriba no se leen igual.
  String rulesChanged(List<String> paths);

  /// El interruptor del visor de documentos. Un documento nace sin poder
  /// ejecutar sus scripts ni salir a la red; esto es cómo se le concede.
  String get allowScriptsAndNetwork;
  String get allowScriptsExplainer;

  /// Lo mismo, en el ancho de un teléfono.
  String get allowScriptsShort;

  /// Qué sale de la máquina: la sección y sus cuatro puertas.
  String get sectionExits;
  String get exitsExplainer;
  String get exitsNoFolder;
  String exitsForFolder(String carpeta);
  String get exitClosed;
  String get exitAvailable;
  String get exitOpen;
  String get exitAnthropic;
  String get exitAnthropicWhat;
  String get exitGemini;
  String get exitGeminiWhat;
  String get exitNotion;
  String get exitNotionWhat;
  String get exitChannel;
  String get exitChannelWhat;

  /// El registro de la app, en Ajustes › Ayuda.
  String get logTitle;
  String get logExplainer;
  String get logAction;
  String get logMissing;
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

mixin ArranqueStringsEs implements ArranqueStrings {
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
  String get guideNotForTitle => 'Para qué no es Nexus';
  @override
  String get guideNotForBody =>
      'Para revisar un diff línea a línea, el terminal o tu editor. Un diff no '
      'se audita de oído, y tampoco de un vistazo a un panel: se lee entero y '
      'con el archivo alrededor. Nexus sirve para despachar el encargo y para '
      'supervisar cómo va; comprobar lo que salió es otra cosa, y se hace mejor '
      'donde siempre.\n\n'
      'Para una sesión larga delante de la pantalla, también el terminal. Nexus '
      'está diseñado para que no estés mirando —el atajo sin traer la ventana, '
      'el icono de la barra, el aviso al terminar—. Si vas a estar delante toda '
      'la tarde, ahí tienes más sitio y menos intermediarios.\n\n'
      'Y para nada que no necesite esta máquina. Lo que Nexus hace y la nube no '
      'es justo eso: tus simuladores, tu VPN, el .env.local de tu proyecto, el '
      'hot reload de un proceso vivo. Un encargo que solo necesita el '
      'repositorio lo hará igual de bien cualquier otro cliente, y con menos '
      'piezas por medio.\n\n'
      'Decirlo es parte del trato: a una herramienta que dice para qué no sirve '
      'es a la única a la que se le puede creer cuando dice para qué sí.';
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
  String get hayMasAbajo => 'Hay más abajo';
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
  String rulesChanged(List<String> paths) =>
      'Han cambiado las reglas que Claude lee antes de cada encargo: '
      '${paths.join(', ')}. El encargo sigue.';
  @override
  String get allowScriptsAndNetwork => 'Permitir scripts y red';
  @override
  String get allowScriptsExplainer =>
      'Este documento lo escribió Claude. Sin esto no ejecuta sus scripts ni '
      'carga nada de internet.';
  @override
  String get allowScriptsShort => 'Scripts y red';
  @override
  String get sectionExits => 'Qué sale';
  @override
  String get exitsExplainer =>
      'Las cuatro puertas por las que algo puede salir de este Mac, con lo que '
      'viaja por cada una y si está saliendo ahora. Aquí no se configura nada: '
      'cada puerta se decide en su propio ajuste. Esto es para poder mirarlas '
      'juntas.';
  @override
  String get exitsNoFolder => 'SIN CARPETA ENFOCADA';
  @override
  String exitsForFolder(String carpeta) => 'PARA $carpeta';
  @override
  String get exitClosed => 'cerrada';
  @override
  String get exitAvailable => 'puede abrirse';
  @override
  String get exitOpen => 'saliendo';
  @override
  String get exitAnthropic => 'Anthropic';
  @override
  String get exitAnthropicWhat =>
      'Lo que Claude lee de tu carpeta, en cada encargo. Es cómo trabaja: sin '
      'esto no hay producto.';
  @override
  String get exitGemini => 'Google · voz';
  @override
  String get exitGeminiWhat =>
      'Tu micrófono y lo que Claude leyó, porque una respuesta narrada lo lleva '
      'dentro. En una carpeta de solo texto no participa.';
  @override
  String get exitNotion => 'Notion';
  @override
  String get exitNotionWhat =>
      'Conversaciones enteras, al terminar cada turno. Archivar en una carpeta '
      'o en Obsidian no sale de aquí: es disco de este Mac.';
  @override
  String get exitChannel => 'El canal del teléfono';
  @override
  String get exitChannelWhat =>
      'Lo que se ve y se dice en la app, dentro de tu tailnet. Escribir pide '
      'además la frase, y caduca sola.';
  @override
  String get logTitle => 'REGISTRO';
  @override
  String get logExplainer =>
      'Lo que Nexus ha ido contando de sí mismo, escrito en un archivo. Sirve '
      'para cuando algo falla y hay que saber qué pasó antes. No sale de este '
      'Mac: se queda en su carpeta y lo lees tú.';
  @override
  String get logAction => 'Ver en el Finder';
  @override
  String get logMissing => 'Todavía no hay nada escrito.';
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

mixin ArranqueStringsEn implements ArranqueStrings {
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
  String get guideNotForTitle => 'What Nexus is not for';
  @override
  String get guideNotForBody =>
      'To review a diff line by line, the terminal or your editor. A diff is '
      'not audited by ear, and not at a glance in a panel either: it is read '
      'whole, with the file around it. Nexus is for dispatching the errand and '
      'for supervising how it goes; checking what came out is another thing, '
      'and it is done better where it always was.\n\n'
      'For a long session in front of the screen, the terminal too. Nexus is '
      'designed for you not to be watching — the shortcut that does not bring '
      'the window forward, the menu bar icon, the notice when it finishes. If '
      'you are going to sit there all afternoon, that gives you more room and '
      'fewer middlemen.\n\n'
      'And for anything that does not need this machine. What Nexus does and '
      'the cloud cannot is exactly that: your simulators, your VPN, your '
      "project's .env.local, hot reload of a live process. An errand that only "
      'needs the repository will be done just as well by any other client, with '
      'fewer pieces in the way.\n\n'
      'Saying so is part of the deal: a tool that says what it is not for is '
      'the only one you can believe when it says what it is for.';
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
  String get hayMasAbajo => 'There is more below';
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
  String rulesChanged(List<String> paths) =>
      'The rules Claude reads before every errand have changed: '
      '${paths.join(', ')}. The errand carries on.';
  @override
  String get allowScriptsAndNetwork => 'Allow scripts and network';
  @override
  String get allowScriptsExplainer =>
      'Claude wrote this document. Without this it runs no scripts and loads '
      'nothing from the internet.';
  @override
  String get allowScriptsShort => 'Scripts & network';
  @override
  String get sectionExits => 'What leaves';
  @override
  String get exitsExplainer =>
      'The four doors anything can leave this Mac through, what travels out of '
      'each and whether it is leaving right now. Nothing is configured here: '
      'each door is decided in its own setting. This is for seeing them '
      'together.';
  @override
  String get exitsNoFolder => 'NO FOLDER IN FOCUS';
  @override
  String exitsForFolder(String carpeta) => 'FOR $carpeta';
  @override
  String get exitClosed => 'closed';
  @override
  String get exitAvailable => 'can open';
  @override
  String get exitOpen => 'leaving';
  @override
  String get exitAnthropic => 'Anthropic';
  @override
  String get exitAnthropicWhat =>
      'What Claude reads from your folder, on every errand. It is how it works: '
      'without this there is no product.';
  @override
  String get exitGemini => 'Google · voice';
  @override
  String get exitGeminiWhat =>
      'Your microphone and what Claude read, because a narrated answer carries '
      'it inside. In a text-only folder it takes no part.';
  @override
  String get exitNotion => 'Notion';
  @override
  String get exitNotionWhat =>
      'Whole conversations, at the end of every turn. Archiving to a folder or '
      'to Obsidian does not leave here: that is this Mac\'s disk.';
  @override
  String get exitChannel => 'The phone channel';
  @override
  String get exitChannelWhat =>
      'What the app shows and says, inside your tailnet. Writing also takes the '
      'phrase, and it expires on its own.';
  @override
  String get logTitle => 'LOG';
  @override
  String get logExplainer =>
      'What Nexus has been saying about itself, written to a file. It is for '
      'when something breaks and you need to know what happened before. It '
      'never leaves this Mac: it stays in its folder and you are the one who '
      'reads it.';
  @override
  String get logAction => 'Show in Finder';
  @override
  String get logMissing => 'Nothing written yet.';
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

/// Las pruebas de la app.
///
/// Dónde viven, cómo se listan, y el repo remoto del que salen y al que
/// vuelven.
///
/// Los tres van juntos —lo que se declara y sus dos traducciones— porque lo
/// que se rompe es la terna: añadir un texto y olvidar un idioma. Tenerlos en
/// el mismo archivo hace que el hueco se vea al escribirlo, no al compilar.
mixin PruebasStrings {
  // Dónde viven las pruebas de una carpeta.
  String testsFolderTitle(String folder);
  String get testsFolderExplainer;
  String get testsFolderHint;
  String testsFolderResolved(String path);
  String get testsFolderPick;
  // La sección de Pruebas: una raíz común y el listado por proyecto.
  String get sectionPruebas;
  String get sectionCuentas;
  String get flowsRootExplainer;
  String get flowsRootHint;
  String get flowsByProject;
  String get flowsNoProjects;
  String get flowsNoneHere;
  String flowsCount(int total);

  /// El desplegable de qué proyecto mirar, cuando hay más de uno emparejado.
  String get e2eWhichProject;
  // Pruebas de la app
  String get e2eTitle;
  // Repo de pruebas remoto
  String get e2eRepoTitle;
  String get e2eRepoUpdating;
  String get e2eRepoUpToDate;
  String get e2eRepoCloned;
  String get e2eRepoDirty;
  String get e2eRepoFailed;
  String get e2eRepoNoFlows;
  String get e2eRepoRetry;
  String get e2eRepoNeedsDevice;
  String get e2eRepoSearch;
  String get e2ePublish;
  String get e2ePublishTitle;
  String e2ePublishWhere(String slug, String ruta);
  String get e2ePublishReplaces;
  String get e2ePublishNew;
  String get e2ePublishHow;
  String get e2ePublishMessage;
  String get e2ePublishDoing;
  String get e2ePublishPushedOnly;
  String get e2ePublishFailed;
  String get e2ePublishNoRepo;
  String get e2ePublishOpen;
  String get e2eRepoGroupTests;
  String get e2eRepoGroupPieces;
  String e2eRepoMatches(int cuantos, int total);
  String e2eRepoFlows(int total);
  String get e2eAccounts;
  String get e2eAccountsTitle;
  String get e2eAccountsNone;
  String get e2eAccountsWhere;
  String get e2eAccountDefault;
  String get e2eAccountMakeDefault;
  String get e2eAccountAdd;
  String get e2eAccountKey;
  String get e2eAccountKeyHint;
  String get e2eAccountTags;
  String get e2eAccountTagsHint;
  String get e2eAccountDesc;
  String get e2eAccountDescHint;
  String get e2eAccountsNoneAnywhere;
  String get e2eAccountsNoneHere;
  String get e2eAccountVars;
  String get e2eAccountVarsHint;
  String get e2eAccountSave;
  String get e2eAccountDelete;
  String get e2eNone;
  String get e2eNoRuns;
  String get e2eRun;
  String get e2eStop;
  String get e2eDelete;
  String get e2eUnattributed;
  String get e2ePassed;
  String get e2eFailed;
  String get e2eRunningNow;
  String get e2eUnknown;
  String get e2eNoDevice;
  String get e2eDevice;
  String get e2eDeleteTest;
  String get e2eDeleteTestAsk;
  String get e2eDeleteTestAskLost;
  String get e2eDeleteTestAskPlain;
  String get e2eSee;
  String get e2eRunningTitle;
  String get e2eStartDevice;
  String get e2eStarting;
  String get e2eNotInstalled;
  String get e2eRepeat;
  String get e2eFlowGone;
  String get e2eDeleteProject;
  String get e2eDeleteProjectAsk;
  String e2eRunsSize(int cuantas, String tamano);
  String e2eMissingVars(String claves);
  String e2eVarsLoaded(int cuantas);
  String get e2eEnvInGit;
  String get e2eDriverBlocked;
  String get e2eNoTapPermission;
  String get e2eAppMissing;
  String get e2eSearchingDevices;
  String get verLaPantalla;
  String get verLaPantallaSinTocar;
  String get verElIphoneDuplicado;
  String get verElIphoneQuickTime;
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
  String get repoDeclaraTitle;
  String get repoDeclaraExplainer;
  String get repoSoloTexto;
  String get repoSoloLectura;
  String repoComandosVetados(int cuantos);
  String repoCarpetaDePruebas(String carpeta);
  String repoModelo(String modelo);
  String get repoAvisosTitle;
  String get repoLoFija;
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
}

mixin PruebasStringsEs implements PruebasStrings {
  @override
  String testsFolderTitle(String folder) => 'Las pruebas de «$folder»';
  @override
  String get testsFolderExplainer =>
      'Dónde buscarlas. Vacío es «.maestro/» dentro del proyecto, que es la convención '
      'de Maestro. Apuntando cada proyecto a su propia carpeta, sus pruebas no se '
      'mezclan con las de otro: Nexus lista esa y no ve las demás. Se lista plano, así '
      'que lo que guardes en subcarpetas —los flows que otros llaman— queda fuera.';
  @override
  String get testsFolderHint => '~/Escritorio/e2e/global66   ·   o «flows»';
  @override
  String testsFolderResolved(String path) => 'Buscará en $path';
  @override
  String get testsFolderPick => 'Elegir…';
  @override
  String get sectionPruebas => 'Pruebas';
  @override
  String get sectionCuentas => 'Cuentas de prueba';
  @override
  String get flowsRootExplainer =>
      'Una carpeta para las pruebas de todos los proyectos, con una subcarpeta por cada '
      'uno: «~/pruebas/nexus». Así están juntas y fuera de los repos —una prueba dentro '
      'de un repo del trabajo es un archivo que alguien acaba commiteando— y aun así no '
      'se mezclan, porque cada proyecto lista la suya. Vacío deja a cada uno con su '
      '«.maestro/», que es la convención de Maestro.';
  @override
  String get flowsRootHint => '~/pruebas';
  @override
  String get flowsByProject => 'Por proyecto';
  @override
  String get flowsNoProjects => 'No hay ninguna carpeta emparejada todavía.';
  @override
  String get flowsNoneHere => 'ninguna';
  @override
  String flowsCount(int total) => total == 1 ? '1 prueba' : '$total pruebas';
  @override
  String get e2eWhichProject => 'De qué proyecto';
  @override
  String get e2eTitle => 'Pruebas de la app';
  @override
  String get e2eRepoTitle => 'Repo de pruebas';
  @override
  String get e2eRepoUpdating => 'Poniendo al día…';
  @override
  String get e2eRepoUpToDate => 'Al día';
  @override
  String get e2eRepoCloned => 'Clonado';
  @override
  String get e2eRepoDirty => 'Con cambios sin publicar; no lo toco';
  @override
  String get e2eRepoFailed => 'No pude sincronizar';
  @override
  String get e2eRepoNoFlows => 'El repo no tiene flows todavía.';
  @override
  String get e2eRepoRetry => 'Reintentar';
  @override
  String get e2eRepoNeedsDevice =>
      'Falta elegir dónde correr, en el selector de arriba.';
  @override
  String get e2eRepoSearch => 'Buscar una prueba';
  @override
  String get e2ePublish => 'Publicar al repo de pruebas';
  @override
  String get e2ePublishTitle => 'Publicar al repo';
  @override
  String e2ePublishWhere(String slug, String ruta) => 'Va a $slug, en $ruta';
  @override
  String get e2ePublishReplaces =>
      'Ya hay un archivo con ese nombre: el PR lo reemplaza.';
  @override
  String get e2ePublishNew => 'Es un archivo nuevo en el repo.';
  @override
  String get e2ePublishHow =>
      'Se crea una rama y se abre un PR contra main. No se mezcla nada: eso lo decide quien lo revise.';
  @override
  String get e2ePublishMessage => 'Mensaje del commit';
  @override
  String get e2ePublishDoing => 'Publicando…';
  @override
  String get e2ePublishPushedOnly =>
      'Empujado a la rama. El PR ábrelo tú: no pude usar gh.';
  @override
  String get e2ePublishFailed => 'No se pudo publicar';
  @override
  String get e2ePublishNoRepo =>
      'El repo de pruebas no está listo todavía. Abre el panel de pruebas y espera a que se clone.';
  @override
  String get e2ePublishOpen => 'Abrir el PR';
  @override
  String get e2eRepoGroupTests => 'Pruebas';
  @override
  String get e2eRepoGroupPieces => 'Piezas de otros flows';
  @override
  String e2eRepoMatches(int cuantos, int total) =>
      cuantos == total ? '$total' : '$cuantos de $total';
  @override
  String e2eRepoFlows(int total) => total == 1 ? '1 flow' : '$total flows';
  @override
  String get e2eAccounts => 'Cuentas';
  @override
  String get e2eAccountsTitle => 'Cuentas de prueba';
  @override
  String get e2eAccountsNone =>
      'No hay ninguna cuenta. Sin una, ningún flow puede correr: Maestro necesita las credenciales una por una.';
  @override
  String get e2eAccountsWhere =>
      'Se guardan en esta máquina y nunca dentro del repo, que es de donde se empuja.';
  @override
  String get e2eAccountDefault => 'por defecto';
  @override
  String get e2eAccountMakeDefault => 'Hacer por defecto';
  @override
  String get e2eAccountAdd => 'Añadir cuenta';
  @override
  String get e2eAccountKey => 'Clave';
  @override
  String get e2eAccountKeyHint => 'El nombre corto de la cuenta: pe, co, mx';
  @override
  String get e2eAccountTags => 'Etiquetas';
  @override
  String get e2eAccountTagsHint =>
      'Separadas por coma y sin el acct- de delante. Ej: pe, any';
  @override
  String get e2eAccountDesc => 'Descripción';
  @override
  String get e2eAccountDescHint =>
      'Para qué sirve. Ej: PEN verificada, sin Bre-B';
  @override
  String get e2eAccountsNoneAnywhere =>
      'Ningún proyecto tiene cuentas todavía. Sin una, sus pruebas no pueden correr.';
  @override
  String get e2eAccountsNoneHere =>
      'Este proyecto no tiene cuentas. Se crean en Ajustes → Cuentas de prueba.';
  @override
  String get e2eAccountVars => 'Variables';
  @override
  String get e2eAccountVarsHint =>
      'Una por línea, CLAVE=valor. Mínimo: APP_ID, EMAIL, PASSWORD, PIN_1..4';
  @override
  String get e2eAccountSave => 'Guardar';
  @override
  String get e2eAccountDelete => 'Borrar cuenta';
  @override
  String get e2eNone => 'Este proyecto no tiene pruebas en .maestro/';
  @override
  String get e2eNoRuns =>
      'Todavía no hay pasadas. Las que lances desde aquí aparecerán con su proyecto.';
  @override
  String get e2eRun => 'Correr';
  @override
  String get e2eStop => 'Cortar';
  @override
  String get e2eDelete => 'Borrar';
  @override
  String get e2eUnattributed => 'Sin proyecto';
  @override
  String get e2ePassed => 'pasó';
  @override
  String get e2eFailed => 'falló';
  @override
  String get e2eRunningNow => 'corriendo';
  @override
  String get e2eUnknown => 'sin saber';
  @override
  String get e2eNoDevice => 'Hace falta un dispositivo encendido';
  @override
  String get e2eDevice => 'Dónde correrla';
  @override
  String get e2eDeleteTest => 'Borrar la prueba';
  @override
  String get e2eDeleteTestAsk =>
      'Borra el archivo del repo. Se recupera con git.';
  @override
  String get e2eDeleteTestAskLost =>
      'Este archivo no está en git: si lo borras, se pierde.';
  @override
  String get e2eDeleteTestAskPlain => 'Borra el archivo del repo.';
  @override
  String get e2eSee => 'Ver';
  @override
  String get e2eRunningTitle => 'Corriendo';
  @override
  String get e2eStartDevice => 'Arrancar un emulador';
  @override
  String get e2eStarting => 'Arrancando el emulador…';
  @override
  String get e2eNotInstalled =>
      'La app no está instalada en ese dispositivo. Maestro no la instala: córrela primero con ▶.';
  @override
  String get e2eRepeat => 'Repetir';
  @override
  String get e2eFlowGone =>
      'Esa prueba ya no está en el repo, así que no se puede repetir.';
  @override
  String get e2eDeleteProject => 'Borrar las pasadas de este proyecto';
  @override
  String get e2eDeleteProjectAsk =>
      'Borra todas las pasadas de este proyecto. Las pruebas no se tocan.';
  @override
  String e2eRunsSize(int cuantas, String tamano) =>
      '${cuantas == 1 ? '1 pasada' : '$cuantas pasadas'} · $tamano';
  @override
  String e2eMissingVars(String claves) => 'Faltan en .env.local: $claves';
  @override
  String e2eVarsLoaded(int cuantas) => cuantas == 1
      ? '1 variable de .env.local'
      : '$cuantas variables de .env.local';
  @override
  String get e2eEnvInGit =>
      '.env.local está en git. Sácalo: lleva credenciales.';
  @override
  String get e2eDriverBlocked =>
      'El dispositivo no dejó instalar el driver de Maestro. En Xiaomi hace falta '
      '«Instalar vía USB» y «Depuración USB (Ajustes de seguridad)» en opciones de '
      'desarrollador; se apagan solas cada cierto tiempo.';
  @override
  String get e2eNoTapPermission =>
      'El dispositivo deja leer la pantalla pero no tocarla. En Xiaomi es '
      '«Depuración USB (Ajustes de seguridad)»: sin ella los assert pasan y el tap '
      'falla.';
  @override
  String get e2eAppMissing =>
      'La app no estaba en el dispositivo. Maestro no la instala: córrela primero.';
  @override
  String get e2eSearchingDevices => 'Buscando dispositivos…';
  @override
  String get verLaPantalla => 'Ver la pantalla del móvil';
  @override
  String get verLaPantallaSinTocar =>
      'Ver la pantalla, sin control: hay una prueba corriendo';
  @override
  String get verElIphoneDuplicado =>
      'Duplicado de iPhone: con control. Pide el mismo Apple ID y el teléfono '
      'bloqueado y cerca.';
  @override
  String get verElIphoneQuickTime =>
      'QuickTime: por cable y sin control. La fuente se elige dentro de QuickTime.';
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
  String get repoDeclaraTitle => 'LO QUE DECLARA ESTE REPOSITORIO';
  @override
  String get repoDeclaraExplainer =>
      'Sale de su «.nexus/config.json», versionado dentro del repositorio y '
      'revisable en un PR. Solo puede apretar: apaga cosas, nunca las '
      'enciende, y tu cuenta de Claude no se lee nunca de ahí.';
  @override
  String get repoSoloTexto => 'Nada de aquí sale hacia el servicio de voz.';
  @override
  String get repoSoloLectura =>
      'Aquí no se escribe, esté como esté el interruptor de arriba.';
  @override
  String repoComandosVetados(int cuantos) => cuantos == 1
      ? 'Un comando vetado más, sumado a los tuyos.'
      : '$cuantos comandos vetados más, sumados a los tuyos.';
  @override
  String repoCarpetaDePruebas(String carpeta) =>
      'Sus pruebas están en «$carpeta».';
  @override
  String repoModelo(String modelo) =>
      'Propone $modelo, y solo si tú no has elegido.';
  @override
  String get repoAvisosTitle => 'Y esto lo trae mal, así que no se aplica:';
  @override
  String get repoLoFija => 'Lo fija el repositorio';
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
}

mixin PruebasStringsEn implements PruebasStrings {
  @override
  String testsFolderTitle(String folder) => 'The tests for «$folder»';
  @override
  String get testsFolderExplainer =>
      'Where to look for them. Empty means «.maestro/» inside the project, which is '
      "Maestro's convention. Point each project at its own folder and its tests cannot "
      'mix with another\'s: Nexus lists that one and never sees the rest. Listing is '
      'flat, so whatever you keep in subfolders — the flows others call — stays out.';
  @override
  String get testsFolderHint => '~/Desktop/e2e/global66   ·   or «flows»';
  @override
  String testsFolderResolved(String path) => 'Will look in $path';
  @override
  String get testsFolderPick => 'Choose…';
  @override
  String get sectionPruebas => 'Tests';
  @override
  String get sectionCuentas => 'Test accounts';
  @override
  String get flowsRootExplainer =>
      'One folder for every project\'s tests, with a subfolder per project: '
      '«~/tests/nexus». Together and outside the repos — a test inside a work repo is a '
      'file somebody eventually commits — and still not mixed, because each project '
      'lists its own. Empty leaves each one with its «.maestro/», which is Maestro\'s '
      'convention.';
  @override
  String get flowsRootHint => '~/tests';
  @override
  String get flowsByProject => 'By project';
  @override
  String get flowsNoProjects => 'No folder paired yet.';
  @override
  String get flowsNoneHere => 'none';
  @override
  String flowsCount(int total) => total == 1 ? '1 test' : '$total tests';
  @override
  String get e2eWhichProject => 'Which project';
  @override
  String get e2eTitle => 'App tests';
  @override
  String get e2eRepoTitle => 'Tests repo';
  @override
  String get e2eRepoUpdating => 'Syncing…';
  @override
  String get e2eRepoUpToDate => 'Up to date';
  @override
  String get e2eRepoCloned => 'Cloned';
  @override
  String get e2eRepoDirty => 'Has unpublished changes; leaving it alone';
  @override
  String get e2eRepoFailed => 'Could not sync';
  @override
  String get e2eRepoNoFlows => 'The repo has no flows yet.';
  @override
  String get e2eRepoRetry => 'Retry';
  @override
  String get e2eRepoNeedsDevice =>
      'Pick where to run it, in the selector above.';
  @override
  String get e2eRepoSearch => 'Find a test';
  @override
  String get e2ePublish => 'Publish to the tests repo';
  @override
  String get e2ePublishTitle => 'Publish to the repo';
  @override
  String e2ePublishWhere(String slug, String ruta) => 'Goes to $slug, at $ruta';
  @override
  String get e2ePublishReplaces =>
      'A file with that name is already there: the PR replaces it.';
  @override
  String get e2ePublishNew => 'It is a new file in the repo.';
  @override
  String get e2ePublishHow =>
      'A branch is created and a PR opened against main. Nothing is merged: whoever reviews it decides that.';
  @override
  String get e2ePublishMessage => 'Commit message';
  @override
  String get e2ePublishDoing => 'Publishing…';
  @override
  String get e2ePublishPushedOnly =>
      'Pushed to the branch. Open the PR yourself: gh was not available.';
  @override
  String get e2ePublishFailed => 'Could not publish';
  @override
  String get e2ePublishNoRepo =>
      'The tests repo is not ready yet. Open the tests panel and wait for the clone.';
  @override
  String get e2ePublishOpen => 'Open the PR';
  @override
  String get e2eRepoGroupTests => 'Tests';
  @override
  String get e2eRepoGroupPieces => 'Pieces other flows use';
  @override
  String e2eRepoMatches(int cuantos, int total) =>
      cuantos == total ? '$total' : '$cuantos of $total';
  @override
  String e2eRepoFlows(int total) => total == 1 ? '1 flow' : '$total flows';
  @override
  String get e2eAccounts => 'Accounts';
  @override
  String get e2eAccountsTitle => 'Test accounts';
  @override
  String get e2eAccountsNone =>
      'No accounts yet. Without one no flow can run: Maestro needs the credentials one by one.';
  @override
  String get e2eAccountsWhere =>
      'Kept on this machine and never inside the repo, which is what gets pushed.';
  @override
  String get e2eAccountDefault => 'default';
  @override
  String get e2eAccountMakeDefault => 'Make default';
  @override
  String get e2eAccountAdd => 'Add account';
  @override
  String get e2eAccountKey => 'Key';
  @override
  String get e2eAccountKeyHint => 'The account short name: pe, co, mx';
  @override
  String get e2eAccountTags => 'Tags';
  @override
  String get e2eAccountTagsHint =>
      'Comma separated, without the leading acct-. E.g. pe, any';
  @override
  String get e2eAccountDesc => 'Description';
  @override
  String get e2eAccountDescHint =>
      'What it is for. E.g. PEN verified, no Bre-B';
  @override
  String get e2eAccountsNoneAnywhere =>
      'No project has accounts yet. Without one, its tests cannot run.';
  @override
  String get e2eAccountsNoneHere =>
      'This project has no accounts. They are created in Settings → Test accounts.';
  @override
  String get e2eAccountVars => 'Variables';
  @override
  String get e2eAccountVarsHint =>
      'One per line, KEY=value. At least: APP_ID, EMAIL, PASSWORD, PIN_1..4';
  @override
  String get e2eAccountSave => 'Save';
  @override
  String get e2eAccountDelete => 'Delete account';
  @override
  String get e2eNone => 'This project has no tests in .maestro/';
  @override
  String get e2eNoRuns =>
      'No runs yet. The ones you launch here will show up with their project.';
  @override
  String get e2eRun => 'Run';
  @override
  String get e2eStop => 'Stop';
  @override
  String get e2eDelete => 'Delete';
  @override
  String get e2eUnattributed => 'No project';
  @override
  String get e2ePassed => 'passed';
  @override
  String get e2eFailed => 'failed';
  @override
  String get e2eRunningNow => 'running';
  @override
  String get e2eUnknown => 'unknown';
  @override
  String get e2eNoDevice => 'A running device is needed';
  @override
  String get e2eDevice => 'Where to run it';
  @override
  String get e2eDeleteTest => 'Delete the test';
  @override
  String get e2eDeleteTestAsk =>
      'Deletes the file from the repo. Recoverable with git.';
  @override
  String get e2eDeleteTestAskLost =>
      'This file is not in git: deleting it loses it.';
  @override
  String get e2eDeleteTestAskPlain => 'Deletes the file from the repo.';
  @override
  String get e2eSee => 'Open';
  @override
  String get e2eRunningTitle => 'Running';
  @override
  String get e2eStartDevice => "Start an emulator";
  @override
  String get e2eStarting => "Starting the emulator…";
  @override
  String get e2eNotInstalled =>
      "The app is not installed on that device. Maestro will not install it: run it first with ▶.";
  @override
  String get e2eRepeat => 'Repeat';
  @override
  String get e2eFlowGone =>
      'That test is no longer in the repo, so it cannot be repeated.';
  @override
  String get e2eDeleteProject => "Delete this project's runs";
  @override
  String get e2eDeleteProjectAsk =>
      "Deletes every run of this project. The tests are left alone.";
  @override
  String e2eRunsSize(int cuantas, String tamano) =>
      '${cuantas == 1 ? '1 run' : '$cuantas runs'} · $tamano';
  @override
  String e2eMissingVars(String claves) => 'Missing from .env.local: $claves';
  @override
  String e2eVarsLoaded(int cuantas) => cuantas == 1
      ? '1 variable from .env.local'
      : '$cuantas variables from .env.local';
  @override
  String get e2eEnvInGit =>
      '.env.local is in git. Take it out: it holds credentials.';
  @override
  String get e2eDriverBlocked =>
      "The device refused to install Maestro's driver. On Xiaomi this needs "
      '"Install via USB" and "USB debugging (Security settings)" in developer '
      'options; both switch themselves off periodically.';
  @override
  String get e2eNoTapPermission =>
      'The device lets the screen be read but not touched. On Xiaomi that is '
      '"USB debugging (Security settings)": without it asserts pass and the tap '
      'fails.';
  @override
  String get e2eAppMissing =>
      'The app was not on the device. Maestro does not install it: run it first.';
  @override
  String get e2eSearchingDevices => 'Looking for devices…';
  @override
  String get verLaPantalla => "See the phone's screen";
  @override
  String get verLaPantallaSinTocar =>
      'See the screen, no control: a test is running';
  @override
  String get verElIphoneDuplicado =>
      'iPhone Mirroring: with control. Needs the same Apple ID and the phone '
      'locked and nearby.';
  @override
  String get verElIphoneQuickTime =>
      'QuickTime: over cable, no control. You pick the source inside QuickTime.';
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
  String get repoDeclaraTitle => 'WHAT THIS REPOSITORY DECLARES';
  @override
  String get repoDeclaraExplainer =>
      'It comes from its “.nexus/config.json”, versioned inside the repository '
      'and reviewable in a PR. It can only tighten: it turns things off, never '
      'on, and your Claude account is never read from there.';
  @override
  String get repoSoloTexto => 'Nothing from here goes to the voice service.';
  @override
  String get repoSoloLectura =>
      'Nothing is written here, whatever the switch above says.';
  @override
  String repoComandosVetados(int cuantos) => cuantos == 1
      ? 'One more blocked command, added to yours.'
      : '$cuantos more blocked commands, added to yours.';
  @override
  String repoCarpetaDePruebas(String carpeta) =>
      'Its tests live in “$carpeta”.';
  @override
  String repoModelo(String modelo) =>
      'It proposes $modelo, and only if you have not chosen.';
  @override
  String get repoAvisosTitle => 'And it gets this wrong, so it is not applied:';
  @override
  String get repoLoFija => 'The repository fixes this';
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
}

/// El núcleo.
///
/// La marca, los estados del orbe, las barras, la caja de escribir,
/// la columna de actividad y los rótulos de Ajustes.
///
/// Los tres van juntos —lo que se declara y sus dos traducciones— porque lo
/// que se rompe es la terna: añadir un texto y olvidar un idioma. Tenerlos en
/// el mismo archivo hace que el hueco se vea al escribirlo, no al compilar.
library;

import 'package:nexus/core/i18n/franja_del_dia.dart';

mixin NucleoStrings {
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
  // El permiso que se pregunta
  String permisoPregunta(String herramienta);
  String get permisoEscribe;
  String get permisoConceder;
  String get permisoConcederTodo;
  String get permisoDenegar;
  String get permisoDenegadoMotivo;
  String get permisoCanceladoMotivo;
  String get permisoEnEspera;
  String get permisoDichoConcedido;
  String get permisoDichoConcedidoTodo;
  String get permisoDichoDenegado;
  String get permisoDichoCancelado;
  String contextUsed(int percent);
  String get attachFile;
  String get orbLabel;
  String get orbHint;
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
  String get seeActivity;
  String get expandWindow;
  String get retryErrand;
  String get runThisCommand;
  String saludoDeLaPuerta(FranjaDelDia franja, String? nombre);
  String get laPuertaNoEntendio;
  String laPuertaOyoDos(List<String> carpetas);
  String get stopNow;
  String get restoreWindow;
  String stepsProgress(int done, int total);
  String stepsTaken(int steps);
  String get waitingForOtherConversation;

  /// La espera cuando quien tiene el turno es **esta misma conversación**,
  /// comprimiéndose. Culparla de «la otra conversación» con una sola abierta se
  /// lee como un cuelgue, y se reportó como tal.
  String get waitingForOwnCompaction;
  String get waitingByVoice;
  String get noFolderForConversation;

  /// Se nombró más de una carpeta: se pregunta en vez de elegir.
  String variasCarpetasNombradas(String cuales);

  /// A dónde se fue el encargo, cuando quien lo pidió no va a verlo llegar.
  String seMandoA(String carpeta);

  /// Habría que abrir una conversación y no caben más.
  String noCabeOtraConversacion(String carpeta);
  String textOnlyFolder(String folder);
  String textOnlyArtifactsFolder(String folder);
  String compacting(int percent);
  String compacted(int before, int after);

  /// Se comprimió, pero todavía no hay medida nueva: llega con el turno
  /// siguiente. Decir una cifra inventada sería peor que no darla.
  String get compactedUnknown;
  // Ajustes
  String get settings;
  String get closeEsc;
  String get sectionVoice;
  String get sectionKeys;
  String get sectionImages;
  String get sectionAvisos;

  /// Los dos nombres: el de quien contesta y el tuyo.
  String get sectionNombres;
  String get nombresExplainer;
  String get comoSeLlamaElAgente;
  String get comoSeLlamaElAgentePista;
  String get comoTeLlamas;
  String get comoTeLlamasPista;
  String get asiSeVera;
  String get sinPalabraDeActivacion;
  String ejemploDeLoQuePides(String agente);
  String ejemploDeLoQueContesta(String vocativo);
  String get avisosExplainer;
  String get avisosOn;
  String get avisosCuanto;
  String get avisosCarpeta;
  String get avisosSinCarpeta;
  String get avisosNota;
  String get avisosReleer;
  String get avisosProbar;
  String get avisoDePrueba;
  String get agendaVacia;
  String get agendaFueraDeJornada;
  String agendaDeHoy(int cuantas);
  String get avisosSinLeer;
  String avisosLeidoA(String hora);
  String reunionEnMinutos(String titulo, int minutos);
  String reunionAhora(String titulo);

  /// Lo que se dice cuando el `!` trae algo que no es git.
  String soloGit(String comando);

  /// La cabecera que dice **dónde** se corrió: repo y rama.
  String dondeSeCorrio(String repo, String rama);

  /// Cuando git terminó con error, dicho antes de su propia salida.
  String gitFallo(int codigo);

  /// El pliegue de un bloque de código largo.
  String masLineas(int cuantas);
  String get mostrarMenos;

  /// Un comando que terminó bien y no dijo nada. `git add` es el caso.
  String get sinNadaQueDecir;

  /// Un comando que se quedó colgado y hubo que matarlo.
  String get tardoDemasiado;

  /// No hay carpeta sobre la que correrlo.
  String get sinCarpetaDondeCorrer;

  String get whichImageModel;
  String perImage(String precio);
  String get drawingIt;
  String get imageNeedsKey;
  String get noImageToEdit;
  String get imageNeedsFolder;
  String imageDone(String nombre);

  /// 🔴 **El motivo puede faltar**, y decidir cómo se dice eso es de aquí.
  /// Antes el tipo era `String` y el fallo sin motivo caía por la rama del
  /// éxito: reventaba en un `!` sobre la ruta que no existía.
  String imageFailed(String? motivo);
  String get imagesExplainer;
  String get imageKeyLabel;
  String get imagesNotWiredYet;
  String get keysExplainer;
  String get keyIsSaved;
  String get keyIsMissing;
  String get keyForget;
  String get keyVoice;
  String get keyImages;
  String get defaultAccount;
  String keyImagesFor(String cuenta);
  String get keyChannelToken;
  String get keyWritePhrase;
  String get keyPairing;
  String keyForgetAsk(String llave);
  String get keyForgetWarning;
  String get sectionPermissions;
  String get sectionLanguage;
  String get sectionHistory;
  String get sectionMobile;
}

mixin NucleoStringsEs implements NucleoStrings {
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
  String get canEditExplainer => 'Modifica archivos, preguntando antes';
  @override
  String get readOnlyExplainer => 'Lee y ejecuta, pero no escribe';
  @override
  String permisoPregunta(String herramienta) => '¿Le dejas usar $herramienta?';
  @override
  String get permisoEscribe => 'Esto modifica archivos.';
  @override
  String get permisoConceder => 'Permitir';
  @override
  String get permisoConcederTodo => 'Permitir todo';
  @override
  String get permisoDenegar => 'No';
  @override
  String get permisoDenegadoMotivo => 'No lo autoricé desde Nexus.';
  @override
  String get permisoCanceladoMotivo =>
      'El encargo se detuvo antes de que nadie contestara.';
  @override
  String get permisoEnEspera => 'Esperando tu permiso';
  @override
  String get permisoDichoConcedido => 'Lo permitiste';
  @override
  String get permisoDichoConcedidoTodo =>
      'Lo permitiste, y el resto de la sesión';
  @override
  String get permisoDichoDenegado => 'No lo permitiste';
  @override
  String get permisoDichoCancelado => 'Se detuvo antes de que contestaras';
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
  String get seeActivity => 'Ver lo que está haciendo';
  @override
  String get expandWindow => 'Ampliar';
  @override
  String get retryErrand => 'REINTENTAR';
  @override
  String get runThisCommand => 'CORRER';
  @override
  String saludoDeLaPuerta(FranjaDelDia franja, String? nombre) {
    final hora = switch (franja) {
      FranjaDelDia.manana => 'Buenos días',
      FranjaDelDia.tarde => 'Buenas tardes',
      FranjaDelDia.noche => 'Buenas noches',
    };
    final aQuien = (nombre == null || nombre.isEmpty) ? '' : ', $nombre';
    return '$hora$aQuien. ¿En dónde vamos a trabajar hoy?';
  }

  @override
  String get laPuertaNoEntendio => 'No te seguí. ¿En qué carpeta trabajamos?';
  @override
  String laPuertaOyoDos(List<String> carpetas) =>
      'Oí ${carpetas.join(' y ')}. ¿En cuál de las dos?';
  @override
  String get stopNow => 'Detener el encargo';
  @override
  String get restoreWindow => 'Restaurar';
  @override
  String stepsProgress(int done, int total) => '$done de $total';
  @override
  String stepsTaken(int steps) =>
      steps == 1 ? 'VER EL PASO QUE DIO' : 'VER LOS $steps PASOS QUE DIO';
  @override
  String get waitingForOtherConversation =>
      'Esperando a la otra conversación sobre esta carpeta';
  @override
  String get waitingForOwnCompaction =>
      'Comprimiendo esta conversación: tu encargo entra en cuanto termine';
  @override
  String get waitingByVoice =>
      'Espero turno: hay otra conversación trabajando en esa carpeta.';
  @override
  String get noFolderForConversation =>
      'Esta conversación no tiene carpeta emparejada: no hay dónde trabajar.';
  @override
  String variasCarpetasNombradas(String cuales) =>
      'Nombraste varias carpetas —$cuales— y no elijo por ti: '
      'de la carpeta salen la cuenta y los permisos. Di solo una.';
  @override
  String seMandoA(String carpeta) =>
      'Lo mandé a «$carpeta», que es la carpeta que nombraste. El trabajo sale por ahí.';
  @override
  String noCabeOtraConversacion(String carpeta) =>
      'Para trabajar en «$carpeta» hace falta otra conversación y no caben más. '
      'Cierra una y lo repito.';
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
  String get settings => 'AJUSTES';
  @override
  String get closeEsc => 'CERRAR  ESC';
  @override
  String get sectionVoice => 'Voz';
  @override
  String get sectionKeys => 'Llaves';
  @override
  String get sectionImages => 'Imágenes';
  @override
  String get sectionAvisos => 'Avisos';
  @override
  String get sectionNombres => 'Nombres';
  @override
  String get nombresExplainer =>
      'La app se seguirá llamando Nexus: eso va compilado dentro. Lo que se '
      'elige aquí es cómo se llama quien te contesta, y cómo quieres que te '
      'llame a ti.';
  @override
  String get comoSeLlamaElAgente => 'Cómo se llama quien te contesta';
  @override
  String get comoSeLlamaElAgentePista => 'Nexus';
  @override
  String get comoTeLlamas => 'Cómo quieres que te llame';
  @override
  String get comoTeLlamasPista => 'Tu nombre, o vacío para que no te llame';
  @override
  String get asiSeVera => 'Así se verá';
  @override
  String get sinPalabraDeActivacion =>
      'Ponerle nombre no hace que despierte al decirlo: la voz se sigue '
      'abriendo con ⌥Espacio. Sí entiende que le hablas a ella si la nombras '
      'por escrito.';
  @override
  String ejemploDeLoQuePides(String agente) =>
      '$agente, ¿qué reuniones tengo hoy?';
  @override
  String ejemploDeLoQueContesta(String vocativo) =>
      '${vocativo}tienes tres: la primera a las nueve.';
  @override
  String get avisosExplainer =>
      'Nexus te dice en voz alta que tienes una reunión, unos minutos antes. Es '
      'lo único que hace sin que se lo pidas, así que nace apagado.\n\nMira el '
      'calendario de la cuenta de Claude de la carpeta que elijas, y solo avisa '
      'de lo que tiene invitados: los bloques tuyos no suenan.';
  @override
  String get avisosOn => 'Avisarme de las reuniones';
  @override
  String get avisosCuanto => 'CUÁNTO ANTES';
  @override
  String get avisosCarpeta => 'DE QUÉ CUENTA MIRA EL CALENDARIO';
  @override
  String get avisosSinCarpeta => 'Elige una carpeta';
  @override
  String get avisosReleer => 'ACTUALIZAR EL CALENDARIO';
  @override
  String get avisosProbar => 'OÍR UN AVISO';
  @override
  String get avisoDePrueba => 'Reunión de prueba';
  @override
  String get agendaVacia => 'Hoy no tienes reuniones.';
  @override
  String get agendaFueraDeJornada =>
      'La jornada terminó y la agenda del día ya no está en memoria. Si la '
      'necesitas, actualízala en Ajustes › Avisos.';
  @override
  String agendaDeHoy(int cuantas) => cuantas == 1
      ? 'Hoy tienes una reunión:'
      : 'Hoy tienes $cuantas reuniones:';
  @override
  String get avisosSinLeer => 'todavía sin leer';
  @override
  String avisosLeidoA(String hora) => 'leído a las $hora';
  @override
  String get avisosNota =>
      'Suena con la voz que elegiste en Voz, y también en el teléfono si está '
      'conectado. Si estás hablando con Nexus, espera a que la conversación '
      'termine; si no termina, lo deja en una notificación.';
  @override
  String reunionEnMinutos(String titulo, int minutos) =>
      '$titulo, en $minutos minutos.';
  @override
  String reunionAhora(String titulo) => '$titulo, ahora.';
  @override
  String get whichImageModel => 'CON QUÉ MODELO SE DIBUJA';
  @override
  String perImage(String precio) => '$precio por imagen';
  @override
  String soloGit(String comando) =>
      'Por ahora «!» solo corre git, y eso era «$comando». Lo demás se le pide '
      'a Claude sin el «!».';
  @override
  String dondeSeCorrio(String repo, String rama) => '$repo · $rama';
  @override
  String gitFallo(int codigo) => 'git terminó con error (código $codigo):';
  @override
  String masLineas(int cuantas) => '$cuantas líneas más';
  @override
  String get mostrarMenos => 'Mostrar menos';
  @override
  String get sinNadaQueDecir =>
      'Hecho. git no dijo nada, que suele ser buena señal.';
  @override
  String get tardoDemasiado =>
      'Se estaba tardando demasiado y lo corté. Si pedía una contraseña, no hay '
      'quien la escriba desde aquí: ese va en la terminal.';
  @override
  String get sinCarpetaDondeCorrer =>
      'No hay ninguna carpeta abierta sobre la que correrlo.';
  @override
  String get drawingIt => 'Generando la imagen…';
  @override
  String get imageNeedsKey =>
      'Falta la llave de imágenes. Se pone en Ajustes → Imágenes.';
  @override
  String get noImageToEdit =>
      'No hay ninguna imagen que editar en esta conversación. Pide una con '
      '«/imagen» y luego cámbiala con «/edita».';
  @override
  String get imageNeedsFolder =>
      'No hay carpeta de documentos donde dejarla. Se elige en Ajustes.';
  @override
  String imageDone(String nombre) => 'Listo: $nombre';
  @override
  String imageFailed(String? motivo) => motivo == null || motivo.isEmpty
      ? 'No se pudo generar la imagen.'
      : 'No se pudo generar la imagen: $motivo';
  @override
  String get imagesExplainer =>
      'La llave con la que se generan las imágenes. Va aparte de la de voz '
      'porque su proyecto necesita '
      'facturación: con una sola, encender las imágenes empezaría a cobrar '
      'también las conversaciones.\n\nY hay una por cuenta de Claude: el gasto '
      'sale de un bolsillo concreto, así que ponerla solo en una cuenta es la '
      'forma de decir que desde las demás no se generan imágenes.';
  @override
  String get imageKeyLabel => 'LLAVE DE IMÁGENES (GEMINI)';
  @override
  String get imagesNotWiredYet =>
      'Se pide con «/imagen» y lo que escribas detrás. Cada imagen se cobra de '
      'tu saldo.';
  @override
  String get keysExplainer =>
      'Lo que Nexus tiene guardado cifrado en este Mac. No se enseña ninguna: '
      'solo si está puesta o no. Para comprobar si es la que crees, quítala y '
      'pon la buena.';
  @override
  String get keyIsSaved => 'guardada';
  @override
  String get keyIsMissing => 'sin poner';
  @override
  String get keyForget => 'OLVIDAR';
  @override
  String get keyVoice => 'Llave de voz (Gemini)';
  @override
  String get keyImages => 'Llave de imágenes (Gemini)';
  @override
  String get defaultAccount => 'cuenta por defecto';
  @override
  String keyImagesFor(String cuenta) => 'Llave de imágenes · $cuenta';
  @override
  String get keyChannelToken => 'Token del canal';
  @override
  String get keyWritePhrase => 'Frase de escritura';
  @override
  String get keyPairing => 'Emparejamiento del teléfono';
  @override
  String keyForgetAsk(String llave) => '¿Olvidar «$llave»?';
  @override
  String get keyForgetWarning =>
      'Se borra del llavero y no se puede deshacer. Habrá que volver a ponerla.';
  @override
  String get sectionPermissions => 'Permisos';
  @override
  String get sectionLanguage => 'Idioma';
  @override
  String get sectionMobile => 'Móvil';
  @override
  String get sectionHistory => 'Historial';
}

mixin NucleoStringsEn implements NucleoStrings {
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
  String get canEditExplainer => 'Changes files, asking first';
  @override
  String get readOnlyExplainer => 'Reads and runs, but never writes';
  @override
  String permisoPregunta(String herramienta) => 'Let it use $herramienta?';
  @override
  String get permisoEscribe => 'This changes files.';
  @override
  String get permisoConceder => 'Allow';
  @override
  String get permisoConcederTodo => 'Allow all';
  @override
  String get permisoDenegar => 'No';
  @override
  String get permisoDenegadoMotivo => "I didn't allow it from Nexus.";
  @override
  String get permisoCanceladoMotivo =>
      'The errand stopped before anyone answered.';
  @override
  String get permisoEnEspera => 'Waiting for your answer';
  @override
  String get permisoDichoConcedido => 'You allowed it';
  @override
  String get permisoDichoConcedidoTodo =>
      'You allowed it, and the rest of the session';
  @override
  String get permisoDichoDenegado => "You didn't allow it";
  @override
  String get permisoDichoCancelado => 'It stopped before you answered';
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
  String get seeActivity => 'See what it is doing';
  @override
  String get expandWindow => 'Expand';
  @override
  String get retryErrand => 'RETRY';
  @override
  String get runThisCommand => 'RUN';
  @override
  String saludoDeLaPuerta(FranjaDelDia franja, String? nombre) {
    final hora = switch (franja) {
      FranjaDelDia.manana => 'Good morning',
      FranjaDelDia.tarde => 'Good afternoon',
      FranjaDelDia.noche => 'Good evening',
    };
    final aQuien = (nombre == null || nombre.isEmpty) ? '' : ', $nombre';
    return '$hora$aQuien. Where are we working today?';
  }

  @override
  String get laPuertaNoEntendio => "I didn't catch that. Which folder?";
  @override
  String laPuertaOyoDos(List<String> carpetas) =>
      'I heard ${carpetas.join(' and ')}. Which one?';
  @override
  String get stopNow => 'Stop the errand';
  @override
  String get restoreWindow => 'Restore';
  @override
  String stepsProgress(int done, int total) => '$done of $total';
  @override
  String stepsTaken(int steps) =>
      steps == 1 ? 'SEE THE STEP IT TOOK' : 'SEE THE $steps STEPS IT TOOK';
  @override
  String get waitingForOtherConversation =>
      'Waiting for the other conversation on this folder';
  @override
  String get waitingForOwnCompaction =>
      'Compacting this conversation: your errand starts as soon as it ends';
  @override
  String get waitingByVoice =>
      'I am waiting my turn: another conversation is working on that folder.';
  @override
  String get noFolderForConversation =>
      'This conversation has no folder paired: there is nowhere to work.';
  @override
  String variasCarpetasNombradas(String cuales) =>
      'You named several folders — $cuales — and I will not pick for you: '
      'the account and the permissions come from the folder. Name just one.';
  @override
  String seMandoA(String carpeta) =>
      'Sent it to "$carpeta", the folder you named. The work happens there.';
  @override
  String noCabeOtraConversacion(String carpeta) =>
      'Working in "$carpeta" needs another conversation and there is no room. '
      'Close one and I will repeat it.';
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
  String get settings => 'SETTINGS';
  @override
  String get closeEsc => 'CLOSE  ESC';
  @override
  String get sectionVoice => 'Voice';
  @override
  String get sectionKeys => 'Keys';
  @override
  String get sectionImages => 'Images';
  @override
  String get sectionAvisos => 'Alerts';
  @override
  String get sectionNombres => 'Names';
  @override
  String get nombresExplainer =>
      'The app will still be called Nexus: that is compiled in. What you pick '
      'here is what the one answering you is called, and how you want to be '
      'addressed.';
  @override
  String get comoSeLlamaElAgente => 'What the one answering is called';
  @override
  String get comoSeLlamaElAgentePista => 'Nexus';
  @override
  String get comoTeLlamas => 'How you want to be addressed';
  @override
  String get comoTeLlamasPista => 'Your name, or empty for none';
  @override
  String get asiSeVera => 'How it will look';
  @override
  String get sinPalabraDeActivacion =>
      'Naming it does not make it wake on hearing that name: voice still opens '
      'with ⌥Space. It does understand you are addressing it when you write '
      'the name.';
  @override
  String ejemploDeLoQuePides(String agente) =>
      '$agente, what meetings do I have today?';
  @override
  String ejemploDeLoQueContesta(String vocativo) =>
      '${vocativo}you have three: the first at nine.';
  @override
  String get avisosExplainer =>
      'Nexus tells you out loud that you have a meeting, a few minutes before. '
      'It is the only thing it does without being asked, so it starts off.\n\nIt '
      'looks at the calendar of the Claude account of the folder you pick, and '
      'only announces what has guests: your own blocks stay quiet.';
  @override
  String get avisosOn => 'Tell me about meetings';
  @override
  String get avisosCuanto => 'HOW LONG BEFORE';
  @override
  String get avisosCarpeta => 'WHOSE CALENDAR IT LOOKS AT';
  @override
  String get avisosSinCarpeta => 'Pick a folder';
  @override
  String get avisosReleer => 'REFRESH THE CALENDAR';
  @override
  String get avisosProbar => 'HEAR AN ALERT';
  @override
  String get avisoDePrueba => 'Test meeting';
  @override
  String get agendaVacia => 'You have no meetings today.';
  @override
  String get agendaFueraDeJornada =>
      'The day is over and the agenda is no longer in memory. Refresh it in '
      'Settings › Alerts if you need it.';
  @override
  String agendaDeHoy(int cuantas) => cuantas == 1
      ? 'You have one meeting today:'
      : 'You have $cuantas meetings today:';
  @override
  String get avisosSinLeer => 'not read yet';
  @override
  String avisosLeidoA(String hora) => 'read at $hora';
  @override
  String get avisosNota =>
      'It speaks with the voice you picked under Voice, and on the phone too if '
      'it is connected. If you are talking to Nexus it waits for the '
      'conversation to end; if it does not, it leaves a notification.';
  @override
  String reunionEnMinutos(String titulo, int minutos) =>
      '$titulo, in $minutos minutes.';
  @override
  String reunionAhora(String titulo) => '$titulo, now.';
  @override
  String get whichImageModel => 'WHICH MODEL DRAWS';
  @override
  String perImage(String precio) => '$precio per image';
  @override
  String soloGit(String comando) =>
      '"!" only runs git for now, and that was "$comando". Everything else goes '
      'to Claude without the "!".';
  @override
  String dondeSeCorrio(String repo, String rama) => '$repo · $rama';
  @override
  String gitFallo(int codigo) => 'git exited with an error (code $codigo):';
  @override
  String masLineas(int cuantas) => '$cuantas more lines';
  @override
  String get mostrarMenos => 'Show less';
  @override
  String get sinNadaQueDecir =>
      'Done. git said nothing, which is usually a good sign.';
  @override
  String get tardoDemasiado =>
      'It was taking too long, so I cut it off. If it was asking for a password, '
      'there is nobody here to type it: run that one in the terminal.';
  @override
  String get sinCarpetaDondeCorrer => 'There is no open folder to run it in.';
  @override
  String get drawingIt => 'Generating the image…';
  @override
  String get imageNeedsKey =>
      'The image key is missing. Set it in Settings → Images.';
  @override
  String get noImageToEdit =>
      'There is no image to edit in this conversation. Ask for one with '
      '"/imagen" and then change it with "/edita".';
  @override
  String get imageNeedsFolder =>
      'There is no documents folder to put it in. Pick one in Settings.';
  @override
  String imageDone(String nombre) => 'Done: $nombre';
  @override
  String imageFailed(String? motivo) => motivo == null || motivo.isEmpty
      ? 'Could not generate the image.'
      : 'Could not generate the image: $motivo';
  @override
  String get imagesExplainer =>
      'The key images are generated with. It is separate from the voice one '
      'because its project needs '
      'billing: with a single key, turning images on would start charging for '
      'conversations too.\n\nAnd there is one per Claude account: the spend '
      'comes out of a specific pocket, so setting it on one account only is how '
      'you say images are not generated from the others.';
  @override
  String get imageKeyLabel => 'IMAGE KEY (GEMINI)';
  @override
  String get imagesNotWiredYet =>
      'Ask for one with "/imagen" and whatever you type after it. Each image is '
      'charged to your balance.';
  @override
  String get keysExplainer =>
      'What Nexus keeps encrypted on this Mac. None of them is shown: only '
      'whether it is set. To check whether it is the one you think, remove it '
      'and put the right one in.';
  @override
  String get keyIsSaved => 'saved';
  @override
  String get keyIsMissing => 'not set';
  @override
  String get keyForget => 'FORGET';
  @override
  String get keyVoice => 'Voice key (Gemini)';
  @override
  String get keyImages => 'Image key (Gemini)';
  @override
  String get defaultAccount => 'default account';
  @override
  String keyImagesFor(String cuenta) => 'Image key · $cuenta';
  @override
  String get keyChannelToken => 'Channel token';
  @override
  String get keyWritePhrase => 'Write phrase';
  @override
  String get keyPairing => 'Phone pairing';
  @override
  String keyForgetAsk(String llave) => 'Forget "$llave"?';
  @override
  String get keyForgetWarning =>
      'It is deleted from the keychain and cannot be undone. You will have to '
      'set it again.';
  @override
  String get sectionPermissions => 'Permissions';
  @override
  String get sectionLanguage => 'Language';
  @override
  String get sectionMobile => 'Mobile';
  @override
  String get sectionHistory => 'History';
}

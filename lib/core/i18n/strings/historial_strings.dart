/// El historial y el archivo.
///
/// Las conversaciones guardadas y a dónde se archivan.
///
/// Los tres van juntos —lo que se declara y sus dos traducciones— porque lo
/// que se rompe es la terna: añadir un texto y olvidar un idioma. Tenerlos en
/// el mismo archivo hace que el hueco se vea al escribirlo, no al compilar.
mixin HistorialStrings {
  // Historial
  String get history;
  String get slackTitle;
  String get slackExplainer;
  String get slackConToken;
  String get slackSinToken;
  String get slackTokenHint;
  String get slackDestino;
  String get slackDestinoHint;
  String get slackDestinoExplainer;
  String get slackProyecto;
  String get slackTodos;
  String get slackProbar;
  String get slackProbando;
  String get slackPrueba;
  String get slackLlego;
  String get parteDelDia;
  String get parteSinDia;
  String get parteAlSlack;
  String get parteEnviado;
  String parteFallo(String motivo);

  String get historyExplainer;
  String get nothingAskedYet;
  String startFromScratchIn(String folder);
  String get conversationForgotten;
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
}

mixin HistorialStringsEs implements HistorialStrings {
  @override
  String get slackTitle => 'EL PARTE DEL DÍA, A SLACK';
  @override
  String get slackExplainer =>
      'Claude escribe el parte de tu último día de trabajo y lo puedes mandar a '
      'Slack. Nunca sale solo: se lee aquí antes y sale si le das.';
  @override
  String get slackConToken => 'Hay un token guardado.';
  @override
  String get slackSinToken =>
      'No hay token. Se crea una app en tu espacio de Slack con el permiso '
      'chat:write y se pega aquí.';
  @override
  String get slackTokenHint => 'xoxb-… o xoxp-…';
  @override
  String get slackDestino => 'A QUIÉN SE LE MANDA';
  @override
  String get slackDestinoHint => 'U01ABCDEFG';
  @override
  String get slackDestinoExplainer =>
      'Tu propio identificador de usuario, para que llegue a tu conversación '
      'contigo. Sale del perfil de Slack, en «Copiar identificador de miembro».';
  @override
  String get slackProyecto => 'DE QUÉ PROYECTO';
  @override
  String get slackTodos => 'todos';
  @override
  String get slackProbar => 'Mandar una de prueba';
  @override
  String get slackProbando => 'Mandando…';
  @override
  String get slackPrueba => 'Prueba desde Nexus. Si lees esto, la puerta abre.';
  @override
  String get slackLlego => 'Llegó.';
  @override
  String get parteDelDia => 'Parte del día';
  @override
  String get parteSinDia =>
      'No hay ningún día anterior con trabajo que contar.';
  @override
  String get parteAlSlack => 'Mandar a Slack';
  @override
  String get parteEnviado => 'Enviado';
  @override
  String parteFallo(String motivo) => 'No se pudo enviar: $motivo';
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
}

mixin HistorialStringsEn implements HistorialStrings {
  @override
  String get slackTitle => 'THE DAY’S REPORT, TO SLACK';
  @override
  String get slackExplainer =>
      'Claude writes the report of your last working day and you can send it to '
      'Slack. It never goes on its own: you read it here first.';
  @override
  String get slackConToken => 'There is a token saved.';
  @override
  String get slackSinToken =>
      'No token. Create an app in your Slack workspace with the chat:write '
      'scope and paste it here.';
  @override
  String get slackTokenHint => 'xoxb-… or xoxp-…';
  @override
  String get slackDestino => 'WHO IT GOES TO';
  @override
  String get slackDestinoHint => 'U01ABCDEFG';
  @override
  String get slackDestinoExplainer =>
      'Your own member ID, so it lands in your conversation with yourself. It '
      'is in your Slack profile, under “Copy member ID”.';
  @override
  String get slackProyecto => 'WHICH PROJECT';
  @override
  String get slackTodos => 'all';
  @override
  String get slackProbar => 'Send a test one';
  @override
  String get slackProbando => 'Sending…';
  @override
  String get slackPrueba =>
      'Test from Nexus. If you are reading this, the door opens.';
  @override
  String get slackLlego => 'It arrived.';
  @override
  String get parteDelDia => 'Day’s report';
  @override
  String get parteSinDia => 'There is no earlier day with work to report.';
  @override
  String get parteAlSlack => 'Send to Slack';
  @override
  String get parteEnviado => 'Sent';
  @override
  String parteFallo(String motivo) => 'Could not send: $motivo';
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
}

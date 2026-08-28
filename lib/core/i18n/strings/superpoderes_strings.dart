/// Los superpoderes.
///
/// Servidores MCP, skills y plugins de cada cuenta.
///
/// Los tres van juntos —lo que se declara y sus dos traducciones— porque lo
/// que se rompe es la terna: añadir un texto y olvidar un idioma. Tenerlos en
/// el mismo archivo hace que el hueco se vea al escribirlo, no al compilar.
mixin SuperpoderesStrings {
  // Superpoderes: servidores MCP de cada cuenta.
  String get sectionSuperpowers;
  String get sectionEmulators;
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
  String durationMinutes(int minutes);
  String durationHoursMinutes(int hours, int minutes);
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
}

mixin SuperpoderesStringsEs implements SuperpoderesStrings {
  @override
  String get sectionSuperpowers => 'Superpoderes';
  @override
  String get sectionEmulators => 'Emuladores';
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
  String durationMinutes(int minutes) => '$minutes min';
  @override
  String durationHoursMinutes(int hours, int minutes) =>
      minutes == 0 ? '$hours h' : '$hours h $minutes min';
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
}

mixin SuperpoderesStringsEn implements SuperpoderesStrings {
  @override
  String get sectionSuperpowers => 'Superpowers';
  @override
  String get sectionEmulators => 'Emulators';
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
  String durationMinutes(int minutes) => '$minutes min';
  @override
  String durationHoursMinutes(int hours, int minutes) =>
      minutes == 0 ? '$hours h' : '$hours h $minutes min';
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
}

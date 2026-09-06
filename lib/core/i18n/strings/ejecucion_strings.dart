/// Correr la app.
///
/// Emuladores, dispositivos y la corrida en marcha.
///
/// Los tres van juntos —lo que se declara y sus dos traducciones— porque lo
/// que se rompe es la terna: añadir un texto y olvidar un idioma. Tenerlos en
/// el mismo archivo hace que el hueco se vea al escribirlo, no al compilar.
mixin EjecucionStrings {
  // Emuladores
  String get emulatorsTitle;
  String get emulatorsExplainer;
  String get emulatorsLaunch;
  String get emulatorsClose;
  String get emulatorsRunning;
  String get emulatorsColdBoot;
  String get emulatorsRefresh;
  String get emulatorsEmpty;
  String get emulatorsConnected;
  // Correr la app
  String get runTitle;
  String get runNoConfigs;
  String get runChooseDevice;
  String get runSearchingDevices;
  String get runNoDevices;
  String get runStart;
  String get runStop;
  String get runReload;
  String get runRestart;
  String get runCompiling;
  String get runRunning;
  String get runStopping;
  String get runNoProject;
  String get runLogs;

  /// El registro del **sistema** del dispositivo, que no es el de la corrida:
  /// aquél es lo que imprime la app y este es lo que dice el teléfono.
  String get runSystemLog;
  String get runSystemLogWaiting;
  String get runSystemLogOff;

  /// Los cuatro niveles del filtro, uno por texto y no uno con parámetro: la
  /// forma con parámetro devolvía frases fijas y el argumento no aparecía en
  /// ninguna — lo pescó `diccionario_test`, y con razón.
  String get nivelTodo;
  String get nivelDesdeAvisos;
  String get nivelSoloErrores;
  String get nivelSoloFatales;
  String get runAuto;

  /// La consola de depuración que la app levanta ella misma. **No** es la de
  /// Nexus ni una nuestra: es la de la app que está corriendo.
  String get runConsole;

  /// El asa de la botonera flotante. Es su único rótulo, así que dice lo que la
  /// barra es —lo que está corriendo— y no «arrastrar», que se ve solo.
  String get runToolbarDrag;
}

mixin EjecucionStringsEs implements EjecucionStrings {
  @override
  String get emulatorsTitle => 'Emuladores y simuladores';
  @override
  String get emulatorsExplainer =>
      'Los de esta máquina, con cuáles están arriba. Se arrancan aquí y siguen '
      'vivos aunque cierres Nexus: cerrar la app no te cuesta la sesión.';
  @override
  String get emulatorsLaunch => 'Arrancar';
  @override
  String get emulatorsClose => 'Cerrar';
  @override
  String get emulatorsRunning => 'arriba';
  @override
  String get emulatorsColdBoot => 'en frío';
  @override
  String get emulatorsRefresh => 'Comprobar';
  @override
  String get emulatorsEmpty => 'No hay ninguno en esta máquina.';
  @override
  String get emulatorsConnected => 'Enchufados';
  @override
  String get runTitle => 'Correr la app';
  @override
  String get runNoConfigs =>
      'Este proyecto no declara configuraciones en .vscode/launch.json';
  @override
  String get runChooseDevice => 'Elige un dispositivo';
  @override
  String get runSearchingDevices => 'Buscando dispositivos…';
  @override
  String get runNoDevices => 'Ninguno conectado';
  @override
  String get runStart => 'Correr';
  @override
  String get runStop => 'Parar';
  @override
  String get runReload => 'Recargar';
  @override
  String get runRestart => 'Reiniciar';
  @override
  String get runCompiling => 'Compilando';
  @override
  String get runRunning => 'corriendo';
  @override
  String get runStopping => 'parando';
  @override
  String get runNoProject => 'Sin proyecto no hay nada que correr';
  @override
  String get runLogs => 'Registro';
  @override
  String get runSystemLog => 'Registro del sistema';
  @override
  String get runSystemLogWaiting => 'Escuchando al dispositivo…';
  @override
  String get runSystemLogOff =>
      'Enciéndelo para ver lo que dice el teléfono: los fallos nativos no pasan por la app.';
  @override
  String get nivelTodo => 'todo';
  @override
  String get nivelDesdeAvisos => 'desde avisos';
  @override
  String get nivelSoloErrores => 'solo errores';
  @override
  String get nivelSoloFatales => 'solo fatales';
  @override
  String get runAuto => 'Recargar sola al terminar cada encargo';
  @override
  String get runToolbarDrag => 'Corriendo';
  @override
  String get runConsole => 'Consola de la app';
}

mixin EjecucionStringsEn implements EjecucionStrings {
  @override
  String get emulatorsTitle => 'Emulators and simulators';
  @override
  String get emulatorsExplainer =>
      "The ones on this machine, and which are up. Launch them here and they "
      "stay alive after you quit Nexus: closing the app won't cost you your "
      'session.';
  @override
  String get emulatorsLaunch => 'Launch';
  @override
  String get emulatorsClose => 'Close';
  @override
  String get emulatorsRunning => 'up';
  @override
  String get emulatorsColdBoot => 'cold boot';
  @override
  String get emulatorsRefresh => 'Check';
  @override
  String get emulatorsEmpty => 'None on this machine.';
  @override
  String get emulatorsConnected => 'Plugged in';
  @override
  String get runTitle => 'Run the app';
  @override
  String get runNoConfigs =>
      'This project declares no configurations in .vscode/launch.json';
  @override
  String get runChooseDevice => 'Pick a device';
  @override
  String get runSearchingDevices => 'Looking for devices…';
  @override
  String get runNoDevices => 'None connected';
  @override
  String get runStart => 'Run';
  @override
  String get runStop => 'Stop';
  @override
  String get runReload => 'Reload';
  @override
  String get runRestart => 'Restart';
  @override
  String get runCompiling => 'Compiling';
  @override
  String get runRunning => 'running';
  @override
  String get runStopping => 'stopping';
  @override
  String get runNoProject => 'No project, nothing to run';
  @override
  String get runLogs => 'Log';
  @override
  String get runSystemLog => 'System log';
  @override
  String get runSystemLogWaiting => 'Listening to the device…';
  @override
  String get runSystemLogOff =>
      'Turn it on to see what the phone says: native crashes do not go through the app.';
  @override
  String get nivelTodo => 'everything';
  @override
  String get nivelDesdeAvisos => 'warnings up';
  @override
  String get nivelSoloErrores => 'errors only';
  @override
  String get nivelSoloFatales => 'fatal only';
  @override
  String get runAuto => 'Reload on its own when an errand finishes';
  @override
  String get runToolbarDrag => 'Running';
  @override
  String get runConsole => 'App debug console';
}

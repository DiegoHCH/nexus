import 'dart:io';

/// Cómo se lanza un proceso, **como un dato y no como una llamada fija**.
///
/// 🔴 **Existe porque tres data sources eran imposibles de probar.** Punto 3 del
/// repaso, con los números delante: `corrida_viva.dart` estaba al **0 %** de 47
/// líneas, el de emuladores al **5,7 %** de 106 y el del repo de pruebas al
/// **15,8 %** de 114 — y los tres por lo mismo, no por descuido: llamaban a
/// `Process.start` a pelo, así que probarlos pedía tener un emulador encendido,
/// un `flutter run` de verdad o un repositorio clonado.
///
/// Con el lanzador como parámetro, una prueba puede dar un proceso de mentira y
/// comprobar lo que de verdad se quiere comprobar: **qué se le pide al proceso y
/// qué se hace con lo que contesta**. Eso es lo que se rompe —un argumento en el
/// sitio equivocado no falla, hace otra cosa— y es justo lo que no se veía.
///
/// El valor por defecto es `Process.start`, así que nadie tiene que pasar nada
/// para que siga funcionando igual: la costura solo existe para quien quiera
/// entrar por ella.
typedef LanzarUnProceso =
    Future<Process> Function(
      String ejecutable,
      List<String> argumentos, {
      String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment,
    });

/// Cómo se **corre** un comando y se espera su salida, como un dato.
///
/// El hermano de [LanzarUnProceso] para lo que no es un proceso vivo: `flutter
/// emulators`, `adb devices`, `xcrun simctl`. Mismo motivo y misma medición —el
/// data source de emuladores estaba al **5,7 %** de 106 líneas—: todo pasa por
/// un solo `Process.run`, así que una sola costura abre el archivo entero.
///
/// Lo que se prueba con esto es lo que de verdad se rompe: **cómo se lee lo que
/// contesta**. Un `flutter emulators --machine` que devuelve el JSON por stdout
/// y un «Waiting for another flutter command…» por stderr ya costó un fallo
/// real cuando las dos salidas se juntaban.
///
/// Lleva `workingDirectory` porque el tercero de los tres —el repo de pruebas—
/// corre **todo** dentro de un clon: un `git checkout` lanzado en la carpeta
/// equivocada no falla, cambia de rama en otro repositorio.
typedef CorrerUnComando =
    Future<ProcessResult> Function(
      String ejecutable,
      List<String> argumentos, {
      String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment,
    });

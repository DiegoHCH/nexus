import 'dart:io';

import 'package:flutter/services.dart';

/// Una ventana aparte, escribiendo un archivo.
///
/// El visor de documentos de Nexus es una `NSWindow` con un `WKWebView` que
/// **vigila la carpeta y se recarga cuando cambia**. Escribir una página y
/// pedirle que la abra sale exactamente lo que hace falta cuando algo tarda:
/// una ventana independiente, que se puede mover y dejar al lado, que se
/// actualiza sola y que **no bloquea la app** — al contrario que un diálogo,
/// que se pone encima y no deja hacer otra cosa.
///
/// **Vive aquí porque ya son dos.** Lo escribió la pasada de pruebas, y la
/// actividad de un encargo necesitaba lo mismo. Copiarlo habría dejado dos
/// secuencias del mismo trabajo con dos trampas iguales que recordar, y la que
/// se toque menos acaba discrepando — que es justo lo que pasó con el botón de
/// «ver los archivos que tocó» cuando se mudó de sitio y quedó el viejo.
abstract final class VentanaDelVisor {
  static const _canal = MethodChannel('com.katanalabs.nexus/artifacts');

  /// Escribe [html] en `<raiz>/.ventana/<nombre>.html` y abre su ventana la
  /// primera vez. Después, reescribir la misma ruta actualiza la que ya está
  /// delante: el visor lleva sus ventanas por archivo.
  ///
  /// Devuelve si la página quedó escrita. `false` es «no se pudo», y quien
  /// llama sigue igual: la ventana es una forma de mirar algo, no la cosa.
  static Future<bool> pinta({
    required String raiz,
    required String nombre,
    required String html,
    required bool primeraVez,
    double ancho = 440,
    double alto = 900,
  }) async {
    // Carpeta propia y oculta: es un archivo de trabajo, no algo que mirar en
    // el Finder, y así nadie más escribe donde el visor está vigilando.
    final carpeta = Directory('$raiz/.ventana');
    try {
      carpeta.createSync(recursive: true);
    } on FileSystemException {
      return false;
    }
    final ruta = '${carpeta.path}/$nombre.html';
    try {
      // 🔴 **Se escribe aparte y se renombra encima**, y esto no es prudencia:
      // es lo único que hace que la ventana se entere.
      //
      // El visor vigila el **directorio** con un `DispatchSource`, y eso avisa
      // cuando cambia el *contenido de la carpeta* —un archivo que aparece, se
      // va o se renombra—, **no cuando cambia un archivo que ya estaba
      // dentro**. Sobrescribiendo el mismo archivo no llega ningún evento y la
      // página se queda congelada con el indicador girando por CSS.
      //
      // Un renombrado dentro de la misma carpeta es atómico, así que además
      // nadie lee la página a medio escribir.
      final aparte = File('$ruta.parte')..writeAsStringSync(html);
      aparte.renameSync(ruta);
    } on FileSystemException {
      return false;
    }
    if (!primeraVez) return true;

    try {
      await _canal.invokeMethod<bool>('open', {
        'path': ruta,
        'width': ancho,
        'height': alto,
      });
    } on PlatformException {
      // Sin canal nativo el archivo ya está escrito: se pierde la ventana, no
      // el contenido.
    } on MissingPluginException {
      // En pruebas no hay nadie al otro lado.
    }
    return true;
  }
}

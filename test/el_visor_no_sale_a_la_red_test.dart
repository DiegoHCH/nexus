import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/artifacts/domain/usecases/html_del_visor.dart';

/// SEC-02. Un documento del visor lo escribió Claude, y lo que Claude escribe
/// puede venir influido por lo que leyó en un repositorio. Con la red abierta,
/// mirarlo es darle un canal de salida.

void main() {
  group('la muralla del documento', () {
    test('entra dentro de la cabecera, no al final', () {
      const html =
          '<!doctype html><html><head><title>x</title></head>'
          '<body>hola</body></html>';

      final encerrado = HtmlDelVisor.encerrado(html);

      // Antes del `<title>`: una `Content-Security-Policy` solo gobierna lo que
      // se parsea **después** de ella, así que ponerla al final es ponerla de
      // adorno.
      expect(
        encerrado.indexOf('Content-Security-Policy'),
        lessThan(encerrado.indexOf('<title>')),
      );
    });

    test('sin cabecera se abre una, y detrás del doctype', () {
      const html = '<!DOCTYPE html>\n<body>hola</body>';

      final encerrado = HtmlDelVisor.encerrado(html);

      // El doctype tiene que seguir siendo lo primero: colar algo delante lo
      // invalida y el documento se pinta en modo quirks — un mockup que de
      // repente se ve mal por una medida de seguridad.
      expect(encerrado.trimLeft(), startsWith('<!DOCTYPE html>'));
      expect(encerrado, contains('Content-Security-Policy'));
      expect(
        encerrado.indexOf('Content-Security-Policy'),
        lessThan(encerrado.indexOf('<body>')),
      );
    });

    test('sin doctype ni cabecera, la muralla va primero', () {
      final encerrado = HtmlDelVisor.encerrado('<p>solo un trozo</p>');

      expect(
        encerrado.indexOf('Content-Security-Policy'),
        lessThan(encerrado.indexOf('<p>')),
      );
    });

    // Lo que la política deja fuera es la lista de formas de sacar algo de la
    // máquina; lo que deja pasar es lo que un documento necesita para verse.
    test('lo que se cierra y lo que se deja abierto', () {
      const csp = HtmlDelVisor.csp;

      expect(csp, contains("default-src 'none'"));
      // Sin `script-src` propio: cae en el `default-src 'none'` de arriba.
      expect(csp, isNot(contains('script-src')));
      // Las dos salidas que se olvidan porque no necesitan JavaScript.
      expect(csp, contains("form-action 'none'"));
      expect(csp, contains("base-uri 'none'"));
      // Y lo que sí puede: sus estilos en línea y lo que trae incrustado.
      expect(csp, contains("style-src 'unsafe-inline'"));
      expect(csp, contains('img-src data: blob:'));
      // Las imágenes por URL no, que es una salida con el dato en la dirección.
      expect(csp, isNot(contains('img-src *')));
      expect(csp, isNot(contains('https:')));
    });
  });

  // El molde de arriba puede estar perfecto y no usarlo nadie. Es el hueco por
  // el que ya se coló una vez la cuenta de los documentos: todo compilaba, todo
  // pasaba, y nadie pasaba el dato.
  group('y el visor la usa', () {
    final pagina = File(
      'lib/features/remote/presentation/pages/utility_pages.dart',
    ).readAsStringSync();

    test('el móvil pinta el documento encerrado salvo que se permita', () {
      expect(pagina, contains('HtmlDelVisor.encerrado(widget.html)'));
      expect(
        pagina,
        contains('JavaScriptMode.disabled'),
        reason:
            'la muralla y el modo son dos capas: el modo lo aplica el motor del '
            'webview y la política la aplica el parser',
      );
    });

    test('y nace cerrado', () {
      expect(
        pagina,
        contains('bool _permitido = false'),
        reason: 'un documento recién abierto no ejecuta nada',
      );
    });

    test('el interruptor se ve, y no está escondido en un menú', () {
      expect(pagina, contains('rotulo: strings.allowScriptsShort'));
    });
  });

  group('y el Mac también', () {
    final visor = File('macos/Runner/NexusArtifacts.swift').readAsStringSync();

    // El resto de esto lo comprueban las pruebas nativas, que sí pueden abrir
    // una ventana y preguntarle al DOM. Aquí solo se ata que la decisión siga
    // siendo esa, porque es lo que se lee desde este lado.
    test('el permiso nace apagado y se decide al navegar', () {
      expect(visor, contains('private(set) var permitido = false'));
      expect(
        visor,
        contains('preferences.allowsContentJavaScript = permitido'),
      );
    });

    test('y la lista de bloqueo no usa alternancia, que no compila', () {
      // `^(file|data):` falla con WKErrorDomain 6 y deja el visor sin bloqueo,
      // sin que nada avise al construir el proyecto.
      expect(visor, isNot(contains('url-filter": "^(')));
    });
  });
}

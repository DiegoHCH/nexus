import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/run/domain/usecases/el_registro_como_html.dart';

/// El registro, escrito como una página.
///
/// Lo que se comprueba aquí es lo que se ve al abrirla: que **lo último quede
/// abajo** —que es lo que se busca cuando algo falla—, que una traza no se
/// coma la página, y que los botones sean enlaces que la app sepa atender.
const _textos = TextosDelRegistro(
  titulo: 'Registro',
  dispositivo: 'Medium Phone API 36.1',
  vacio: 'Compilando…',
);

String pagina(
  List<LineaDeLaVentana> lineas, {
  TextosDelRegistro textos = _textos,
  bool viva = true,
  String? escuchandoEn,
  bool escuchando = false,
}) => ElRegistroComoHtml.escribe(
  lineas: lineas,
  textos: textos,
  viva: viva,
  escuchandoEn: escuchandoEn,
  escuchando: escuchando,
);

void main() {
  test('sin nada todavía se dice, en vez de dejarlo en blanco', () {
    // Un hueco negro se lee como roto, y lo que pasa es que aún no ha escrito
    // nadie.
    expect(pagina(const []), contains('Compilando…'));
  });

  // 🔴 **Del revés a propósito.** El rollo es un `column-reverse`: lo primero
  // que se escribe queda abajo, y abajo es donde está lo último que pasó. Es lo
  // que hace que la página recién cargada enseñe el final sin una línea de
  // JavaScript.
  test('lo último va primero, que es lo que queda abajo', () {
    final html = pagina(const [
      LineaDeLaVentana('la primera'),
      LineaDeLaVentana('la última'),
    ]);

    expect(html.indexOf('la última'), lessThan(html.indexOf('la primera')));
  });

  test('una traza no se come el resto de la página', () {
    // No es teórico: cualquier `logcat` de un `WebView` trae etiquetas.
    final html = pagina(const [LineaDeLaVentana('<script>fuego()</script>')]);

    expect(html, isNot(contains('<script>fuego()')));
    expect(html, contains('&lt;script&gt;'));
  });

  test('el nivel pinta la línea, y la etiqueta va delante', () {
    final html = pagina(const [
      LineaDeLaVentana(
        'Fatal signal 11',
        tono: TonoDeLinea.error,
        etiqueta: 'libc',
      ),
      LineaDeLaVentana('skipped frames', tono: TonoDeLinea.aviso),
    ]);

    expect(html, contains('class="l error"'));
    expect(html, contains('class="l aviso"'));
    expect(html, contains('<span class="tag">libc</span>'));
  });

  test('sin escucha que ofrecer no hay chips que pulsar', () {
    // El de la corrida no filtra ni se pausa: sus líneas las trae el daemon.
    expect(pagina(const []), isNot(contains('href="nexus://')));
  });

  test('los botones del sistema son enlaces que la app sabe atender', () {
    final html = pagina(
      const [],
      textos: const TextosDelRegistro(
        titulo: 'Registro del sistema',
        dispositivo: 'Medium Phone API 36.1',
        vacio: 'Escuchando…',
        nivel: 'Desde avisos',
        escucha: 'Registro del sistema',
      ),
      escuchandoEn: 'emulator-5554',
      escuchando: true,
    );

    expect(html, contains('href="nexus://registro/escucha/emulator-5554"'));
    expect(html, contains('href="nexus://registro/nivel"'));
    expect(html, contains('Desde avisos'));
    // Escuchando se ve, o no se sabe si el botón enciende o apaga.
    expect(html, contains('class="chip vivo"'));
  });

  test('parada, la página lo dice: sin indicador de que algo pasa', () {
    expect(pagina(const [], viva: false), isNot(contains('class="gira"')));
    expect(pagina(const []), contains('class="gira"'));
  });
}

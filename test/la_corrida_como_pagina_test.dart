import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/usecases/la_corrida_como_html.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';

/// La corrida escrita como página, que es lo que se ve en la ventana aparte.
void main() {
  test('cada paso lleva la clase de su estado', () {
    final html = LaCorridaComoHtml.escribe(
      flow: 'login',
      pasos: [
        PasoDelFlow(linea: 11, texto: 'uno'),
        PasoDelFlow(linea: 12, texto: 'dos'),
        PasoDelFlow(linea: 13, texto: 'tres'),
      ],
      estados: const [
        EstadoDePaso.hecho,
        EstadoDePaso.fallado,
        EstadoDePaso.pendiente,
      ],
      lineas: const [],
      terminados: 2,
      viva: false,
      fallo: true,
    );

    // Cada fila lleva la clase de su estado, y su número de línea delante.
    expect(html, contains('class="hecho"'));
    expect(html, contains('class="fallo"'));
    expect(html, contains('class="espera"'));
    // **1, 2, 3 y no la línea del archivo.** Se probó con la línea del `.yaml` y
    // salían 12, 22, 27: eso no se lee como una lista de pasos, se lee como un
    // error. La línea sigue estando, en el `title` de la fila.
    expect(html, contains('>1<'));
    expect(html, contains('>3<'));
    expect(html, contains('title="línea 11"'));
  });

  test('**el total va aparte, o sale una cuenta imposible**', () {
    // El fallo que se vio: al abrir el informe de una corrida guardada, la lista
    // de pasos venía vacía y el encabezado decía «8/0». Una cuenta así se lee
    // como un fallo nuestro, y lo era.
    final html = LaCorridaComoHtml.escribe(
      flow: 'login',
      pasos: const [],
      estados: null,
      lineas: const ['Launch app... COMPLETED'],
      terminados: 8,
      total: 8,
      viva: false,
      fallo: false,
    );

    // La cuenta ya no va al lado del título —se quitó a propósito, los números
    // están ahora delante de cada acción— sino en la cabecera de la salida.
    expect(html, contains('8 de 8'));
    expect(html, isNot(contains('8 de 0')));
  });

  test('sin total se usa el número de pasos, que es lo de en vivo', () {
    final html = LaCorridaComoHtml.escribe(
      flow: 'login',
      pasos: [
        PasoDelFlow(linea: 1, texto: 'uno'),
        PasoDelFlow(linea: 2, texto: 'dos'),
      ],
      estados: const [EstadoDePaso.hecho, EstadoDePaso.enCurso],
      lineas: const ['Launch app... COMPLETED'],
      terminados: 1,
      viva: true,
      fallo: false,
    );
    expect(html, contains('1 de 2'));
  });

  test('lo que escribió alguien no puede volverse HTML', () {
    // Un `assertVisible: "<b>"` en un `.yaml`, o una comilla en la salida de
    // Maestro, acaban dentro de esta página.
    final html = LaCorridaComoHtml.escribe(
      flow: 'login',
      pasos: [PasoDelFlow(linea: 1, texto: 'assertVisible: "<b>hola</b>"')],
      estados: const [EstadoDePaso.hecho],
      lineas: const ['algo & otro <cosa>'],
      terminados: 1,
      viva: false,
      fallo: false,
    );

    expect(html, contains('&lt;b&gt;'));
    expect(html, contains('&amp;'));
    expect(html, isNot(contains('<b>hola')));
  });

  test('sin salida no se pinta su sección vacía', () {
    final html = LaCorridaComoHtml.escribe(
      flow: 'login',
      pasos: [PasoDelFlow(linea: 1, texto: 'uno')],
      estados: const [EstadoDePaso.hecho],
      lineas: const [],
      terminados: 1,
      viva: false,
      fallo: false,
    );
    expect(html, isNot(contains('salida')));
  });

  test('autocontenida: nada de fuera', () {
    // La ventana carga un archivo local; cualquier petición a la red sería un
    // hueco en blanco.
    final html = LaCorridaComoHtml.escribe(
      flow: 'login',
      pasos: [PasoDelFlow(linea: 1, texto: 'uno')],
      estados: const [EstadoDePaso.hecho],
      lineas: const [],
      terminados: 1,
      viva: false,
      fallo: false,
    );
    expect(html, isNot(contains('http')));
    expect(html, isNot(contains('<script')));
  });

  group('la etiqueta de estado', () {
    String pagina({required bool viva, required bool fallo}) =>
        LaCorridaComoHtml.escribe(
          flow: 'login',
          pasos: [PasoDelFlow(linea: 1, texto: 'uno')],
          estados: const [EstadoDePaso.hecho],
          lineas: const [],
          terminados: 1,
          viva: viva,
          fallo: fallo,
        );

    test('corriendo, con el indicador girando', () {
      final html = pagina(viva: true, fallo: false);
      expect(html, contains('chapa viva'));
      expect(html, contains('Corriendo'));
      // El giro es CSS: la página no lleva una línea de JavaScript, así que no
      // hay estado que sincronizar entre ella y la app.
      expect(html, contains('class="gira"'));
      expect(html, isNot(contains('<script')));
    });

    test('terminada, con su visto y sin indicador', () {
      final html = pagina(viva: false, fallo: false);
      expect(html, contains('chapa bien'));
      expect(html, contains('Finalizada'));
      expect(html, isNot(contains('class="gira"')));
    });

    test('fallada dice Error, no «terminada»', () {
      final html = pagina(viva: false, fallo: true);
      expect(html, contains('chapa mal'));
      expect(html, contains('Error'));
    });

    test('el botón de detener solo existe mientras corre', () {
      // Y es un enlace a nuestro esquema: el visor lo intercepta y se lo reenvía
      // a la app, que es quien sabe matar el proceso.
      expect(
        pagina(viva: true, fallo: false),
        contains('href="${LaCorridaComoHtml.esquema}://parar"'),
      );
      expect(
        pagina(viva: false, fallo: false),
        isNot(contains('://parar')),
      );
    });
  });

  test('la fila en curso se sombrea, para decir dónde va', () {
    final html = LaCorridaComoHtml.escribe(
      flow: 'login',
      pasos: [
        PasoDelFlow(linea: 1, texto: 'uno'),
        PasoDelFlow(linea: 2, texto: 'dos'),
      ],
      estados: const [EstadoDePaso.hecho, EstadoDePaso.enCurso],
      lineas: const [],
      terminados: 1,
      viva: true,
      fallo: false,
    );
    expect(html, contains('li class="curso"'));
    expect(html, contains('li.curso{background'));
  });

  test('el detalle indentado de un paso se enseña con él', () {
    // Un `tapOn:` a secas no dice nada; el `id:` de debajo es todo el contenido.
    final html = LaCorridaComoHtml.escribe(
      flow: 'login',
      pasos: [
        PasoDelFlow(
          linea: 34,
          texto: 'tapOn:',
          detalle: ['    id: toolbar'],
        ),
      ],
      estados: const [EstadoDePaso.hecho],
      lineas: const [],
      terminados: 1,
      viva: false,
      fallo: false,
    );
    expect(html, contains('id: toolbar'));
    // El paso es el primero, aunque esté en la línea 34.
    expect(html, contains('>1<'));
    expect(html, contains('title="línea 34"'));
  });
}

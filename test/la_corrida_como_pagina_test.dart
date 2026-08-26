import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/usecases/la_corrida_como_html.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';

/// La corrida escrita como página, que es lo que se ve en la ventana aparte.
void main() {
  test('cada paso lleva la clase de su estado', () {
    final html = LaCorridaComoHtml.escribe(
      flow: 'login',
      pasos: ['uno', 'dos', 'tres'],
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

    expect(html, contains('class="hecho">uno<'));
    expect(html, contains('class="fallo">dos<'));
    expect(html, contains('class="espera">tres<'));
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

    expect(html, contains('8/8'));
    expect(html, isNot(contains('8/0')));
  });

  test('sin total se usa el número de pasos, que es lo de en vivo', () {
    final html = LaCorridaComoHtml.escribe(
      flow: 'login',
      pasos: ['uno', 'dos'],
      estados: const [EstadoDePaso.hecho, EstadoDePaso.enCurso],
      lineas: const [],
      terminados: 1,
      viva: true,
      fallo: false,
    );
    expect(html, contains('1/2'));
  });

  test('lo que escribió alguien no puede volverse HTML', () {
    // Un `assertVisible: "<b>"` en un `.yaml`, o una comilla en la salida de
    // Maestro, acaban dentro de esta página.
    final html = LaCorridaComoHtml.escribe(
      flow: 'login',
      pasos: const ['assertVisible: "<b>hola</b>"'],
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
      pasos: const ['uno'],
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
      pasos: const ['uno'],
      estados: const [EstadoDePaso.hecho],
      lineas: const [],
      terminados: 1,
      viva: false,
      fallo: false,
    );
    expect(html, isNot(contains('http')));
    expect(html, isNot(contains('<script')));
  });
}

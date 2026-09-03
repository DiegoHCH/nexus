import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/a_que_carpeta_va.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';

/// Enrutar por voz sin escucha continua.
///
/// 🔴 **El 80 % del valor del spike sin pagar su nudo.** `SPIKE-ESCUCHA.md`
/// cierra diciendo justo esto: el enrutador «se puede construir y probar con
/// `⌥Espacio` y sin escucha continua… y el día que la escucha exista, ya la
/// espera».
///
/// Hoy hay que elegir la carpeta a mano **antes** de hablar, y de ella cuelga
/// todo: la cuenta, el modelo, los permisos y el prompt.
void main() {
  PairedFolder carpeta(String ruta) =>
      PairedFolder(path: ruta, modality: FolderModality.voice);

  final frontMobile = carpeta('/Users/alguien/Workspace/front-mobile-b2c');
  final backendCore = carpeta('/Users/alguien/Workspace/backend-core');
  final nexus = carpeta('/Users/alguien/personal/nexus');
  final todas = [frontMobile, backendCore, nexus];

  AQueCarpetaVa va(String frase, [List<PairedFolder>? donde]) =>
      ACarpetaVaLoQueDices.de(frase, donde ?? todas);

  test('sin nombrar ninguna, no se enruta', () {
    expect(va('arregla el login'), isA<NoSeNombroCarpeta>());
    expect(va(''), isA<NoSeNombroCarpeta>());
  });

  group('nombrando una', () {
    test('se encuentra, y la tarea se queda sin la mención', () {
      final r = va('en el front mobile b2c, arregla el login') as AEstaCarpeta;

      expect(r.carpeta.path, frontMobile.path);
      expect(r.tarea, 'arregla el login');
    });

    // 🔴 Por voz la transcripción **nunca** trae los guiones, y quien escribe
    // tampoco los pone siempre.
    test('da igual cómo se diga el nombre', () {
      for (final frase in [
        'en front-mobile-b2c arregla el login',
        'en front mobile b2c arregla el login',
        'en FRONT_MOBILE_B2C arregla el login',
        'en frontmobileb2c arregla el login',
      ]) {
        final r = va(frase) as AEstaCarpeta;

        expect(r.carpeta.path, frontMobile.path, reason: frase);
        expect(r.tarea, 'arregla el login', reason: frase);
      }
    });

    test('la mención puede ir al final', () {
      final r = va('corre las pruebas del backend core') as AEstaCarpeta;

      expect(r.carpeta.path, backendCore.path);
      expect(r.tarea, 'corre las pruebas');
    });

    test('y en medio', () {
      final r = va('mira en nexus si compila') as AEstaCarpeta;

      expect(r.carpeta.path, nexus.path);
      expect(r.tarea, 'mira si compila');
    });

    test('los acentos no estorban', () {
      final r = va('en nexus, ¿está la versión bien?', [nexus]) as AEstaCarpeta;

      expect(r.tarea, '¿está la versión bien?');
    });

    // Un cambio de carpeta a secas es legítimo: quien llama decide si eso es
    // enfocar y esperar, o preguntar qué hacer.
    test('nombrarla sola deja la tarea vacía, y eso no es un error', () {
      for (final frase in [
        'en el front mobile b2c',
        'front-mobile-b2c',
        'al front mobile b2c',
      ]) {
        final r = va(frase) as AEstaCarpeta;

        expect(r.carpeta.path, frontMobile.path, reason: frase);
        expect(r.tarea, isEmpty, reason: frase);
      }
    });

    // Un verbo de ir que se queda **solo** no es una tarea.
    test('«vete al …» a secas tampoco deja tarea', () {
      for (final frase in [
        'vete al front mobile b2c',
        'cambia al front-mobile-b2c',
        'abre el front mobile b2c',
      ]) {
        expect((va(frase) as AEstaCarpeta).tarea, isEmpty, reason: frase);
      }
    });

    // 🔴 Y esta es la que protege lo anterior: en cuanto hay tarea, **no se
    // toca el verbo**. Adivinar cuáles son de ir dentro de una frase con
    // trabajo es la clase de listeza que acaba tragándose un encargo de verdad.
    test('con tarea detrás, el verbo se queda entero', () {
      final r =
          va('vete al front mobile b2c y arregla el login') as AEstaCarpeta;

      expect(r.tarea, 'vete y arregla el login');
    });
  });

  // 🔴 Misma regla que `RepoFromInstruction`: enrutar a la que no era es peor
  // que no enrutar — desde la que tocaba se ve todo y desde la otra, nada.
  test('nombrando dos no se elige ninguna', () {
    final r =
        va('pasa lo de backend core al front mobile b2c') as SeNombraronVarias;

    expect(
      r.carpetas.map((c) => c.path),
      containsAll([backendCore.path, frontMobile.path]),
    );
  });

  group('lo que no debe enrutar', () {
    // Sin borde, `core` se encontraría dentro de «corenlace».
    test('un nombre dentro de otra palabra no cuenta', () {
      expect(
        va('arregla el backend-coreografia', [backendCore]),
        isA<NoSeNombroCarpeta>(),
      );
      expect(va('mira el nexuses', [nexus]), isA<NoSeNombroCarpeta>());
    });

    // Una carpeta llamada `ui` aparecería dentro de cualquier palabra.
    test('un nombre demasiado corto no se busca', () {
      expect(
        va('arregla la ui del perfil', [carpeta('/Users/alguien/ui')]),
        isA<NoSeNombroCarpeta>(),
      );
    });

    // «Mira en el archivo de configuración» no nombra ninguna carpeta, así que
    // ese «en» no se toca — solo se quita el que introducía la mención.
    test('un «en» que no introducía una carpeta se queda', () {
      final r = va('busca en el archivo de nexus la versión') as AEstaCarpeta;

      expect(
        r.tarea,
        'busca en el archivo la versión',
        reason: 'se quita el «de» pegado a la mención, no el «en» de antes',
      );
    });
  });

  test('sin carpetas emparejadas no hay nada que enrutar', () {
    expect(
      va('en el front mobile arregla esto', const []),
      isA<NoSeNombroCarpeta>(),
    );
  });
}

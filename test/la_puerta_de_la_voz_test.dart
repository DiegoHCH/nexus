import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/repositories/microphone_access.dart';
import 'package:nexus/features/assistant/domain/usecases/la_puerta_de_la_voz.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';

/// Los guardias que hay que pasar para abrir la sesión de voz.
///
/// 🔴 **Es la promesa del producto, escrita en código.** El README dice que una
/// carpeta en solo texto «no abre sesión de voz: nada de esa carpeta viaja a
/// Gemini, ni siquiera el audio», y que es «una negativa, no una preferencia».
/// Quien la cumple es esta escalera, y vivía dentro de un `toggleVoice` de 131
/// líneas sin una prueba que la sujetara.
void main() {
  PairedFolder carpeta({
    String path = '/Users/alguien/repo',
    FolderModality modo = FolderModality.voice,
  }) => PairedFolder(path: path, modality: modo);

  group('lo que estorba sin preguntar nada', () {
    LaPuertaDeLaVoz? estorba({PairedFolder? la, PairedFolder? cajonEn}) =>
        SiSePuedeAbrirLaVoz.loQueEstorba(carpeta: la, duenoDelCajon: cajonEn);

    test('con carpeta de voz y el cajón fuera, nada estorba', () {
      expect(estorba(la: carpeta()), isNull);
    });

    test('sin carpeta emparejada no hay dónde hablar', () {
      expect(estorba(), isA<SinCarpeta>());
    });

    // «Es una negativa, no una preferencia»: no se avisa y se sigue, se rechaza.
    test('una carpeta en solo texto no abre la voz', () {
      final solo = carpeta(modo: FolderModality.textOnly);

      final puerta = estorba(la: solo) as LaCarpetaEsDeSoloTexto;

      expect(puerta.carpeta.path, solo.path);
    });

    // 🔴 El cajón viaja como `--add-dir` en todos los encargos, así que dentro
    // de una carpeta en solo texto sería la fuga por la puerta de atrás.
    test('el cajón dentro de una de solo texto tampoco', () {
      final dueno = carpeta(
        path: '/Users/alguien/privado',
        modo: FolderModality.textOnly,
      );

      final puerta =
          estorba(la: carpeta(), cajonEn: dueno) as ElCajonCaeEnUnaDeSoloTexto;

      expect(puerta.carpeta.path, '/Users/alguien/privado');
    });

    // El orden importa: sin carpeta no se llega a mirar el cajón, y con la
    // carpeta muda tampoco. Lo que se dice es el motivo de más arriba, que es
    // el que se puede arreglar primero.
    test('se dice el primer motivo, no todos', () {
      final dueno = carpeta(
        path: '/Users/alguien/privado',
        modo: FolderModality.textOnly,
      );

      expect(estorba(cajonEn: dueno), isA<SinCarpeta>());
      expect(
        estorba(
          la: carpeta(modo: FolderModality.textOnly),
          cajonEn: dueno,
        ),
        isA<LaCarpetaEsDeSoloTexto>(),
      );
    });
  });

  group('y después el micrófono', () {
    test('concedido, adelante', () {
      expect(
        SiSePuedeAbrirLaVoz.porElMicrofono(MicrophoneStatus.granted),
        isA<SePuedeHablar>(),
      );
    });

    // 🔴 Denegado y sin decidir **no son lo mismo**: uno se arregla en Ajustes
    // del sistema y el otro preguntando, y decir lo mismo en los dos casos
    // manda a la gente al sitio equivocado.
    test('denegado y sin decidir no son lo mismo', () {
      expect(
        SiSePuedeAbrirLaVoz.porElMicrofono(MicrophoneStatus.denied),
        isA<ElMicrofonoEstaBloqueado>(),
      );
      expect(
        SiSePuedeAbrirLaVoz.porElMicrofono(MicrophoneStatus.notAsked),
        isA<HayQuePedirElMicrofono>(),
      );
    });
  });

  // 🔴 Lo que separa las dos mitades, y por qué están separadas: consultar el
  // micrófono toca el canal nativo y pedirlo abre el diálogo del sistema, que
  // espera a una persona. Hacer cualquiera de las dos cosas para acabar negando
  // la sesión por la carpeta es trabajo tirado en el mejor caso y un permiso
  // pedido en falso en el peor.
  test('lo que estorba se decide entero sin tocar el micrófono', () {
    // Si esto necesitara el estado del micrófono, no compilaría: no hay dónde
    // pasárselo. La prueba es la firma.
    expect(
      SiSePuedeAbrirLaVoz.loQueEstorba(
        carpeta: carpeta(modo: FolderModality.textOnly),
        duenoDelCajon: null,
      ),
      isA<LaCarpetaEsDeSoloTexto>(),
    );
  });
}

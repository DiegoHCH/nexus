import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/conversation.dart';
import 'package:nexus/features/assistant/domain/usecases/a_que_carpeta_va.dart';
import 'package:nexus/features/assistant/domain/usecases/que_hacer_con_el_encargo.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';

/// Dónde acaba un encargo que nombra una carpeta.
///
/// 🔴 **La regla que manda: nunca se trabaja en la carpeta que no era.** De la
/// carpeta cuelgan la cuenta, el modelo y los permisos — un encargo en la
/// equivocada puede escribir con la cuenta del trabajo en un repo personal, y
/// eso no se deshace pidiéndolo. Cuando algo no cuadra se dice, no se hace.
void main() {
  PairedFolder carpeta(String ruta) =>
      PairedFolder(path: ruta, modality: FolderModality.voice);

  final aqui = carpeta('/w/nexus');
  final alla = carpeta('/w/front-mobile-b2c');

  Conversations abiertas(List<({String id, String folder})> cuales) =>
      Conversations(
        items: [
          for (final c in cuales) Conversation(id: c.id, folderPath: c.folder),
        ],
        cargado: true,
      );

  QueHacerConElEncargo que(
    AQueCarpetaVa destino, {
    String frase = 'arregla el login',
    String? desde = '/w/nexus',
    Conversations? con,
  }) => QueHacerConLoQueSeDijo.de(
    destino,
    frase: frase,
    carpetaDeAqui: desde,
    abiertas: con ?? abiertas([(id: 'c1', folder: '/w/nexus')]),
  );

  test('sin carpeta nombrada, aquí y tal cual', () {
    final r = que(const NoSeNombroCarpeta()) as AtenderloAqui;

    expect(r.tarea, 'arregla el login');
  });

  // De la carpeta cuelgan la cuenta y los permisos: elegir por la persona es
  // justo lo que no se puede hacer.
  test('nombrando dos, se pregunta y no se hace nada', () {
    final r = que(SeNombraronVarias([aqui, alla])) as PreguntarPorCual;

    expect(r.carpetas, hasLength(2));
  });

  group('nombrando la de aquí', () {
    // Repetir «en nexus» dentro de un encargo que ya corre en nexus es ruido en
    // el prompt, y el prompt se paga.
    test('no se mueve nada, y va la tarea sin la mención', () {
      final r = que(AEstaCarpeta(aqui, 'arregla el login')) as AtenderloAqui;

      expect(r.tarea, 'arregla el login');
    });

    // «Vete a nexus» estando en nexus no es un encargo: se pasa la frase y que
    // decida quien la reciba.
    test('sin tarea se pasa la frase original', () {
      final r =
          que(AEstaCarpeta(aqui, ''), frase: 'vete a nexus') as AtenderloAqui;

      expect(r.tarea, 'vete a nexus');
    });
  });

  group('nombrando otra', () {
    // 🔴 Quien dice «en el front mobile, sigue con esto» quiere la que ya tiene
    // el hilo, no una en blanco que no sabe de qué se hablaba.
    test('si ya hay una abierta ahí, se lleva a ella', () {
      final r =
          que(
                AEstaCarpeta(alla, 'arregla el login'),
                con: abiertas([
                  (id: 'c1', folder: '/w/nexus'),
                  (id: 'c2', folder: '/w/front-mobile-b2c'),
                ]),
              )
              as LlevarloA;

      expect(r.conversacion, 'c2');
      expect(r.tarea, 'arregla el login');
    });

    test('con dos abiertas ahí, la más reciente', () {
      final r =
          que(
                AEstaCarpeta(alla, 'x'),
                con: abiertas([
                  (id: 'vieja', folder: '/w/front-mobile-b2c'),
                  (id: 'nueva', folder: '/w/front-mobile-b2c'),
                ]),
              )
              as LlevarloA;

      expect(r.conversacion, 'nueva');
    });

    test('si no hay ninguna, se abre', () {
      final r = que(AEstaCarpeta(alla, 'arregla el login')) as AbrirUnaPara;

      expect(r.carpeta.path, alla.path);
      expect(r.tarea, 'arregla el login');
    });

    // 🔴 Y si no caben, se dice. Atenderlo aquí en silencio sería hacer el
    // trabajo en la carpeta equivocada, que es lo que todo esto viene a evitar.
    test('si no caben más, se dice en vez de hacerlo aquí', () {
      final r =
          que(
                AEstaCarpeta(alla, 'arregla el login'),
                con: abiertas([
                  for (var i = 0; i < Conversations.max; i++)
                    (id: 'c$i', folder: '/w/otra-$i'),
                ]),
              )
              as NoCabeOtraConversacion;

      expect(r.carpeta.path, alla.path);
    });
  });

  test('sin carpeta aquí, nombrar otra abre la suya', () {
    final r =
        que(AEstaCarpeta(alla, 'x'), desde: null, con: abiertas(const []))
            as AbrirUnaPara;

    expect(r.carpeta.path, alla.path);
  });
}

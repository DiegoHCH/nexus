import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// El `main` del teléfono, vigilado leyendo el archivo.
//
// **Es una prueba rara a propósito**, y existe por un fallo concreto: el `main` del
// móvil pedía la versión del paquete —un canal de plataforma— antes de
// `WidgetsFlutterBinding.ensureInitialized()`. Eso lanza «Binding has not yet been
// initialized», y en el teléfono se ve como una pantalla negra y nada más.
//
// Las 648 pruebas de entonces estaban en verde, y ninguna podía verlo: el arnés de
// pruebas inicializa su propio binding, así que ese `main` **no se ejecuta nunca**
// ahí. Lo destapó arrancar la app en un teléfono de verdad.
//
// Así que se ata leyendo el texto. No es elegante; es lo único que cubre el hueco
// entre «las pruebas pasan» y «la app arranca».
void main() {
  final fuente = File('lib/main_movil.dart').readAsStringSync();

  /// El código **sin comentarios**.
  ///
  /// Hace falta porque la primera versión de esta prueba fallaba con el arreglo ya
  /// puesto: el comentario que explica por qué hay que inicializar el binding
  /// menciona `PackageInfo`, y la prueba encontraba esa mención —antes de la
  /// llamada— y la contaba como uso. Una prueba que se cree los comentarios vigila
  /// la prosa, no el código.
  String sinComentarios(String codigo) => codigo
      .split('\n')
      .map((linea) {
        final corte = linea.indexOf('//');
        return corte < 0 ? linea : linea.substring(0, corte);
      })
      .join('\n');

  test('el main inicializa el binding antes de tocar la plataforma', () {
    final codigo = sinComentarios(fuente);
    final cuerpo = codigo.substring(codigo.indexOf('Future<void> main()'));
    final hastaRunApp = cuerpo.substring(0, cuerpo.indexOf('runApp('));

    // Todo lo que hable con el sistema antes de `runApp` necesita el binding. Si se
    // añade otro —preferencias, llavero, permisos— esta lista tiene que crecer, y el
    // fallo de no crecerla es una pantalla negra.
    const canalesDePlataforma = [
      'PackageInfo',
      'SharedPreferences',
      'MethodChannel',
    ];
    final usados = canalesDePlataforma.where(hastaRunApp.contains).toList();

    if (usados.isEmpty) return;

    final binding = hastaRunApp.indexOf(
      'WidgetsFlutterBinding.ensureInitialized()',
    );
    expect(
      binding,
      isNonNegative,
      reason:
          'el main usa $usados antes de runApp y no inicializa el binding: '
          'la app arranca en negro',
    );
    for (final canal in usados) {
      expect(
        binding,
        lessThan(hastaRunApp.indexOf(canal)),
        reason: '$canal se usa antes de inicializar el binding',
      );
    }
  });

  test('las pantallas del móvil no usan tipografía de escritorio', () {
    // El fallo que esto evita, y pasó: las filas de las listas se escribieron con
    // `NexusTypography.subtitle`, que son **34 px** — un titular de escritorio. En
    // una fila de teléfono ocupa el doble de lo que debe, y cuatro elementos se
    // comían la pantalla. Se vio usándolo: «me parece una exageración lo grande de
    // los items».
    //
    // Los tokens no llevan el tamaño en el nombre, así que `subtitle` suena a algo
    // pequeño y no lo es. Esto ata el nombre al sitio donde vale.
    const soloEscritorio = ['subtitle', 'title', 'hero'];
    final delMovil = Directory('lib/features/remote/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(delMovil, isNotEmpty, reason: 'la carpeta existe');

    final culpables = <String>[];
    for (final f in delMovil) {
      // La sección de Ajustes vive aquí pero es del escritorio: ahí sí valen.
      if (f.path.contains('mobile_section')) continue;
      final fuente = f.readAsStringSync();
      for (final token in soloEscritorio) {
        // Con el nombre **completo**: `contains('subtitle')` encaja también con
        // `subtitleMobile`, que es el correcto — la primera versión de esta prueba
        // señalaba cuatro archivos que estaban bien.
        if (RegExp('NexusTypography\\.$token\\b').hasMatch(fuente)) {
          culpables.add('${f.path.split('/').last} · $token');
        }
      }
    }
    expect(
      culpables,
      isEmpty,
      reason:
          'en un teléfono se usan label(10) · data(11) · mono(13) · body(15) · '
          'lead(17) · subtitleMobile(20)',
    );
  });

  test('el main del escritorio no se toca desde aquí', () {
    // Los dos puntos de entrada son distintos a propósito —el del escritorio arranca
    // atajos, ventana y autoactualizado, y nada de eso existe en un teléfono— y esta
    // prueba solo habla del móvil. Se comprueba que siguen siendo dos, porque si
    // alguien los une, lo que esta prueba vigila deja de estar donde mira.
    expect(File('lib/main.dart').existsSync(), isTrue);
    expect(fuente.contains('NexusMovil'), isTrue);
  });

  test('el archivo del móvil lee la misma fuente que ⌘H', () {
    final hoja = File(
      'lib/features/history/presentation/widgets/conversation_history_sheet.dart',
    ).readAsStringSync();
    final remoto = File(
      'lib/features/remote/presentation/assistant_surface.dart',
    ).readAsStringSync();

    final delEscritorio = RegExp(
      r'ref\.watch\((\w+SavedConversationsProvider)\)',
    ).firstMatch(hoja)?.group(1);
    expect(
      delEscritorio,
      isNotNull,
      reason:
          'la hoja de historial ya no lista con un *SavedConversationsProvider; '
          'mira qué usa ahora y trae el móvil con ella',
    );

    // Los dos métodos, no uno: listar en un sitio y buscar en otro es lo que hacía
    // que retomar una del vault contestara «conversación desconocida».
    for (final metodo in ['archive', 'resumeConversation']) {
      // Por indices y no con una regex: la firma de `archive` ocupa cuatro lineas con
      // llaves de parametros nombrados dentro, y casarla a mano cuesta mas que cortar.
      // El corte es en '\n  }\n' —el cierre del metodo— y no en '\n  }', que es
      // tambien el cierre de los parametros nombrados y dejaba fuera todo el cuerpo.
      final desde = remoto.indexOf('$metodo(');
      expect(
        desde,
        isNot(-1),
        reason: 'no encontre $metodo en la superficie remota',
      );
      final cuerpo = remoto.substring(desde, remoto.indexOf('\n  }\n', desde));
      expect(
        cuerpo,
        contains('$delEscritorio.future'),
        reason:
            '$metodo no lee $delEscritorio: el telefono ensenara menos '
            'conversaciones que la Mac, o no podra abrir las que ensena',
      );
    }
  });
  test('el canal se construye desde el arranque, no solo en su pantalla', () {
    // El fallo que esto ata: durante horas el telefono decia «no se llega» y no habia
    // nada roto en el telefono — el Mac no escuchaba porque lo unico que construia el
    // canal era la seccion «Movil» de Ajustes. El `remote_channel_on` guardado no
    // servia de nada si nadie miraba ese provider.
    //
    // Se comprueba en la raiz de la app y no con un test de widgets porque arrancar
    // la app entera aqui exige llavero, Tailscale y un puerto libre: lo que importa
    // es que **alguien de vida larga** lo mire, y la raiz es ese alguien.
    final raiz = File('lib/main.dart').readAsStringSync();

    expect(
      raiz,
      contains('ref.watch(channelControllerProvider)'),
      reason:
          'sin esto, encender el canal solo dura mientras Ajustes este abierto, y '
          'la promesa de recordarlo es mentira',
    );
  });
}

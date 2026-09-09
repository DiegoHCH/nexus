import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/assistant/domain/usecases/a_donde_va_lo_que_se_escribe.dart';
import 'package:nexus/features/assistant/domain/usecases/los_comandos_de_la_casa.dart';

/// **Los comandos que se escriben con barra, y la lista que los cuenta.**
///
/// 🔴 Nace de una pregunta que **no tenía respuesta dentro de la app**: «qué
/// comandos de terminal puedo usar en Nexus, como el `/clear` de Claude». Los
/// había —`!git`, `/imagen`, `/edita`— y vivían solo en el código: para saber
/// qué se puede escribir había que leer el enrutado. Un atajo que no se puede
/// descubrir es un atajo que no existe.
ADondeVa aDonde(
  String frase, {
  bool esElParte = false,
  bool adjuntos = false,
}) => ADondeVaLoQueSeEscribe.de(
  frase,
  esElParte: esElParte,
  hayAdjuntos: adjuntos,
);

void main() {
  group('los comandos exactos llegan a su sitio', () {
    test('la ayuda, con sus tres formas de escribirse', () {
      for (final forma in ['/ayuda', '/help', '/comandos']) {
        expect(aDonde(forma), isA<ALaAyuda>(), reason: forma);
      }
    });

    // `/clear` es lo que escribe sin pensarlo quien viene de la terminal, y no
    // aceptarlo sería pedirle que aprenda otra palabra para lo mismo.
    test('olvidar acepta también el /clear de la terminal', () {
      for (final forma in ['/olvida', '/olvidar', '/clear']) {
        expect(aDonde(forma), isA<AOlvidar>(), reason: forma);
      }
    });

    // 🔴 Pedido con la referencia delante: «que me mostrara el listado de MCP
    // en el chat, así como se hace en el CLI, con su conectado o desconectado».
    test('los servidores MCP, con sus dos formas', () {
      expect(aDonde('/mcp'), isA<ALosMcp>());
      expect(aDonde('/mcps'), isA<ALosMcp>());
    });

    test('el parte y la agenda, ya sin depender de acertar la frase', () {
      expect(aDonde('/parte'), isA<AlParte>());
      expect(aDonde('/daily'), isA<AlParte>());
      expect(aDonde('/agenda'), isA<ALaAgenda>());
      expect(aDonde('/reuniones'), isA<ALaAgenda>());
    });

    test('en mayúsculas o con espacios de más, igual', () {
      expect(aDonde('  /Ayuda  '), isA<ALaAyuda>());
      expect(aDonde('/CLEAR'), isA<AOlvidar>());
    });
  });

  group('y lo que no es un comando sigue su camino', () {
    // 🔴 **Exacto y no por prefijo.** `/parte` es el comando; «/parte de lo que
    // hablamos ayer» es una frase, y secuestrarla dejaría un encargo sin hacer.
    test('un comando con cola detrás no es el comando', () {
      expect(aDonde('/parte de lo que hablamos ayer'), isA<AClaude>());
      expect(aDonde('/ayuda a entender este método'), isA<AClaude>());
      expect(aDonde('/mcp de jira, cómo se pone'), isA<AClaude>());
    });

    test('los de siempre no se los queda nadie nuevo', () {
      expect(aDonde('!git status'), isA<AlGit>());
      expect(aDonde('/imagen un gato'), isA<ADibujar>());
      expect(aDonde('/edita hazlo más oscuro'), isA<AEditarLaImagen>());
      expect(aDonde('mira el historial'), isA<AClaude>());
    });

    // La regla que ya estaba escrita y no se puede romper: dentro del parte se
    // apaga todo, o un parte que mencione un comando acabaría ejecutándolo.
    test('redactando el parte, ningún comando se reconoce', () {
      expect(aDonde('/ayuda', esElParte: true), isA<AClaude>());
      expect(aDonde('/clear', esElParte: true), isA<AClaude>());
    });

    // Un comando exacto no lleva adjuntos que valgan: quien suelta un archivo y
    // escribe `/ayuda` está pidiendo la ayuda, no mandando el archivo.
    test('y con adjuntos, la ayuda sigue siendo la ayuda', () {
      expect(aDonde('/ayuda', adjuntos: true), isA<ALaAyuda>());
    });
  });

  group('la lista que se enseña', () {
    const textos = NexusStringsEs();

    String laLista() => ElComandoDeLaCasa.laLista(
      textos.ayudaTitulo,
      (comando) => switch (comando) {
        ElComandoDeLaCasa.imagen => textos.ayudaImagen,
        ElComandoDeLaCasa.edita => textos.ayudaEdita,
        ElComandoDeLaCasa.git => textos.ayudaGit,
        ElComandoDeLaCasa.parte => textos.ayudaParte,
        ElComandoDeLaCasa.agenda => textos.ayudaAgenda,
        ElComandoDeLaCasa.mcp => textos.ayudaMcp,
        ElComandoDeLaCasa.olvida => textos.ayudaOlvida,
        ElComandoDeLaCasa.ayuda => textos.ayudaAyuda,
      },
    );

    // 🔴 **La prueba que impide que la ayuda mienta.** Una lista escrita a mano
    // se queda vieja el día que alguien añada un atajo, y una ayuda desfasada
    // es peor que ninguna: manda a escribir cosas que no funcionan. Al salir
    // del catálogo, un comando nuevo aparece solo — y si alguien lo saca de
    // `enLaAyuda`, esto se pone rojo.
    test('están todos los comandos del catálogo, sin faltar ninguno', () {
      final lista = laLista();

      for (final comando in ElComandoDeLaCasa.values) {
        expect(
          lista,
          contains(comando.comoSeEscribe),
          reason: '${comando.name} no se enseña en ninguna parte',
        );
      }
    });

    test('y cada uno dice qué hace y cómo más se puede escribir', () {
      final lista = laLista();

      expect(lista, startsWith(textos.ayudaTitulo));
      expect(lista, contains('/imagen … '), reason: 'lleva texto detrás');
      expect(lista, contains('(/clear, /olvidar)'), reason: 'las otras formas');
      expect(lista, contains(textos.ayudaGit));
      // Una línea por comando y ni una más.
      expect(
        lista.split('\n'),
        hasLength(ElComandoDeLaCasa.enLaAyuda.length + 1),
      );
    });

    test('los dos idiomas la escriben, y ninguno se deja un texto', () {
      for (final textos in [const NexusStringsEs(), const NexusStringsEn()]) {
        for (final texto in [
          textos.ayudaTitulo,
          textos.ayudaImagen,
          textos.ayudaEdita,
          textos.ayudaGit,
          textos.ayudaParte,
          textos.ayudaAgenda,
          textos.ayudaMcp,
          textos.ayudaOlvida,
          textos.ayudaAyuda,
        ]) {
          expect(texto.trim(), isNotEmpty);
        }
      }
    });
  });
}

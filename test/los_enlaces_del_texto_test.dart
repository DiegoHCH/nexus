import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/los_enlaces_del_texto.dart';

/// Los enlaces del chat no estaban rotos: **nunca fueron enlaces**.
///
/// El modelo escribe las URLs entre comillas invertidas casi siempre, y para
/// markdown eso es código. Ni se pulsa, ni se resalta al arrastrar, ni avisa al
/// hacerle clic — tres síntomas distintos con una sola causa, y dos tardes
/// buscándola en el sitio equivocado.
void main() {
  test('una URL citada vuelve a ser una URL', () {
    const dicho =
        'está en esta URL: `https://hysts-mcp-flux-1-dev.hf.space/'
        '--replicas/ppnml/gradio_api/file=/tmp/gradio/070/image.webp`';

    final limpio = LosEnlacesDelTexto.sinComillas(dicho);

    expect(limpio, isNot(contains('`')));
    expect(limpio, contains('https://hysts-mcp-flux-1-dev.hf.space/'));
  });

  // Lo que separa una URL citada de un comando citado es que dentro no haya
  // nada más. Convertir un comando en enlace rompería justo lo que se quería
  // enseñar.
  test('un comando con una URL dentro se queda como está', () {
    const dicho = 'Ejecuta `curl -o x.webp https://ejemplo.dev/x.webp`';

    expect(LosEnlacesDelTexto.sinComillas(dicho), dicho);
  });

  test('el código que no es una URL no se toca', () {
    const dicho = 'Usa `sips -s format png` y luego `flutter test`.';

    expect(LosEnlacesDelTexto.sinComillas(dicho), dicho);
  });

  // Un bloque se escribe para copiarlo tal cual: meterle un enlace cambiaría lo
  // que se copia.
  test('dentro de un bloque de código no se entra', () {
    const dicho =
        'Antes `https://a.dev` y luego:\n'
        '```\ncurl `https://b.dev`\n```\n'
        'y después `https://c.dev`';

    final limpio = LosEnlacesDelTexto.sinComillas(dicho);

    expect(limpio, contains('curl `https://b.dev`'));
    expect(limpio, contains('Antes https://a.dev'));
    expect(limpio, contains('después https://c.dev'));
  });

  // `https://x.dev/a.` se lleva el punto de la frase dentro, y el enlace se
  // abre roto.
  test('el punto final de la frase se queda fuera', () {
    final limpio = LosEnlacesDelTexto.sinComillas('Mira `https://x.dev/a.`');

    expect(limpio, 'Mira https://x.dev/a.');
  });

  test('varias en la misma frase', () {
    final limpio = LosEnlacesDelTexto.sinComillas(
      'Una `https://a.dev` y otra `https://b.dev`',
    );

    expect(limpio, 'Una https://a.dev y otra https://b.dev');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/artifacts/domain/entities/lo_que_salio_del_dibujo.dart';

/// Lo que salió de pedir una imagen, ahora con tipo.
///
/// 🔴 **Era `({String? ruta, String? id, String? problema})` con dos códigos
/// sueltos dentro.** El generador escribía `'sin-llave'` y `'sin-carpeta'`, y el
/// controlador los comparaba con esas mismas cadenas escritas otra vez, en otro
/// archivo, sin nada que atara las dos puntas.
///
/// Y tenía un fallo latente que el tipo destapó: un fallo del modelo **sin
/// motivo** dejaba `problema` en `null`, que era también la señal de éxito. Eso
/// caía por la rama buena y reventaba en el `!` sobre una ruta que no existía.
void main() {
  const es = NexusStringsEs();
  const en = NexusStringsEn();

  /// Cómo se cuenta cada salida. Es lo que se lee en el chat, y las tres que no
  /// son un fallo del modelo se arreglan de maneras distintas: poner la llave,
  /// elegir carpeta, reintentar.
  String comoSeCuenta(LoQueSalioDelDibujo salio, NexusStrings s) =>
      switch (salio) {
        LaImagenSalio(:final ruta) => s.imageDone(ruta.split('/').last),
        FaltaLaLlaveDeImagenes() => s.imageNeedsKey,
        FaltaLaCarpetaDeDocumentos() => s.imageNeedsFolder,
        NoSePudoDibujar(:final motivo) => s.imageFailed(motivo),
      };

  test('la que salió se cuenta por su nombre, no por su ruta', () {
    const salio = LaImagenSalio(
      ruta: '/Users/alguien/documentos/20260903-zorro.png',
      id: 'gen-1',
    );

    expect(comoSeCuenta(salio, es), contains('20260903-zorro.png'));
    expect(
      comoSeCuenta(salio, es),
      isNot(contains('/Users/')),
      reason: 'la ruta entera en el chat no la lee nadie',
    );
  });

  test('los tres motivos no dicen lo mismo', () {
    final dichos = {
      comoSeCuenta(const FaltaLaLlaveDeImagenes(), es),
      comoSeCuenta(const FaltaLaCarpetaDeDocumentos(), es),
      comoSeCuenta(const NoSePudoDibujar('cuota agotada'), es),
    };

    expect(
      dichos,
      hasLength(3),
      reason:
          'se arreglan de maneras distintas —poner la llave, elegir carpeta, '
          'reintentar—, así que contarlos igual manda al sitio equivocado',
    );
  });

  test('el motivo del modelo se enseña tal cual: es accionable', () {
    expect(
      comoSeCuenta(const NoSePudoDibujar('vuelve a intentarlo más tarde'), es),
      contains('vuelve a intentarlo más tarde'),
    );
  });

  // 🔴 El fallo latente. Antes esto no compilaba distinto: entraba por la rama
  // del éxito y reventaba.
  test('un fallo sin motivo se cuenta igual, y no revienta', () {
    for (final s in [es, en]) {
      final dicho = comoSeCuenta(const NoSePudoDibujar(null), s);

      expect(dicho, isNotEmpty);
      expect(dicho, isNot(contains('null')));
    }

    expect(
      comoSeCuenta(const NoSePudoDibujar(''), es),
      comoSeCuenta(const NoSePudoDibujar(null), es),
      reason: 'un motivo vacío es no tener motivo',
    );
  });

  // Solo la que salió puede encadenar un `/edita`: hacerlo sobre una que falló
  // no existe.
  test('solo la que salió trae identificador para encadenar', () {
    expect(const LaImagenSalio(ruta: '/x.png', id: 'gen-1').id, 'gen-1');
    expect(
      const LaImagenSalio(ruta: '/x.png').id,
      isNull,
      reason: 'la API puede no devolverlo, y entonces no se encadena',
    );
  });
}

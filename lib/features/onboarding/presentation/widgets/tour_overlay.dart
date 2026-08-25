import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/onboarding/presentation/providers/tour_providers.dart';
import 'package:nexus/features/onboarding/presentation/state/tour_state.dart';

/// El tour de la primera vez, señalando las piezas de verdad.
///
/// Va encima de **todo** el cuerpo y no dentro del área del orbe: una de las
/// paradas es la barra de arriba, y un velo que no llega hasta ella dejaría
/// media pantalla iluminada sin motivo.
///
/// Arranca en el primer fotograma y no al construir: hasta que el árbol no se ha
/// medido, ninguna pieza tiene rectángulo todavía y el tour no sabría qué puede
/// señalar.
class TourOverlay extends ConsumerStatefulWidget {
  const TourOverlay({super.key});

  @override
  ConsumerState<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends ConsumerState<TourOverlay> {
  /// Se intenta una vez por pantalla. Sin esto se reintentaría en cada
  /// fotograma, y como la preferencia se lee de disco —unos milisegundos— el
  /// primer intento casi siempre llega antes de saber si ya se vio.
  var _tried = false;

  /// Se pinta en el `Overlay` de la app, no donde está declarado.
  ///
  /// Así el velo cubre la ventana entera —incluida la barra de arriba, que es una
  /// de las paradas— sin tener que envolver el `Scaffold` de las dos casas en un
  /// `Stack`. Y de paso los rectángulos, que son globales, coinciden con el
  /// sistema de coordenadas del overlay sin convertir nada.
  final _portal = OverlayPortalController();

  /// La última petición de «verlo otra vez» que este velo ya atendió.
  var _lastRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  void _maybeStart() {
    if (!mounted || _tried) return;
    final anchors = ref.read(tourAnchorsProvider);
    final present = TourStop.values
        .where((stop) => tourRectOf(anchors, stop) != null)
        .toList();
    final started = ref
        .read(tourControllerProvider.notifier)
        .startIfNeeded(present);
    // Solo se marca como intentado cuando de verdad arrancó o cuando ya no hay
    // nada que señalar. Si falló porque la preferencia aún no se había leído,
    // se vuelve a probar en el fotograma siguiente.
    if (started || present.isEmpty) {
      _tried = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  @override
  Widget build(BuildContext context) {
    final tour = ref.watch(tourControllerProvider);
    final corriendo = tour.running;

    // Se pidió repetirlo desde Ajustes: se levanta la marca de «ya intentado» y
    // se vuelve a mirar qué piezas hay.
    if (tour.requests != _lastRequest) {
      _lastRequest = tour.requests;
      _tried = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
    }
    // `show`/`hide` fuera del build: cambiar el overlay mientras se construye
    // dispara un aserto de Flutter.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      corriendo ? _portal.show() : _portal.hide();
    });

    return OverlayPortal(
      controller: _portal,
      // `Positioned.fill` y no el `Stack` a pelo: el hijo del overlay recibe
      // restricciones sueltas, y un `Stack` con todos sus hijos posicionados
      // colapsa a tamaño cero con ellas. Se veía raro de diagnosticar porque los
      // buscadores **sí encontraban** los botones —el widget existe— pero el hit
      // test no daba con nada: no había superficie donde tocar.
      overlayChildBuilder: (context) => Positioned.fill(child: _paso(context)),
      child: const SizedBox.shrink(),
    );
  }

  Widget _paso(BuildContext context) {
    final tour = ref.watch(tourControllerProvider);
    final stop = tour.stop;
    if (stop == null) return const SizedBox.shrink();

    final anchors = ref.watch(tourAnchorsProvider);
    final hole = tourRectOf(anchors, stop);
    // La pieza desapareció mientras se enseñaba —una ventana más pequeña, un
    // cambio de estado—. Se sigue en vez de dibujar un foco sobre la nada.
    if (hole == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(tourControllerProvider.notifier).next(),
      );
      return const SizedBox.shrink();
    }

    final colors = context.colors;
    final strings = context.strings;
    final (titulo, cuerpo) = _copyFor(stop, strings);

    return Stack(
      children: [
        // El velo se traga los toques: durante el tour, tocar el orbe abriría
        // una sesión de voz por detrás de la explicación.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: CustomPaint(
              painter: _Spotlight(
                hole: hole,
                scrim: colors.scrim,
                ring: colors.accent,
              ),
            ),
          ),
        ),
        _Card(
          hole: hole,
          title: titulo,
          body: cuerpo,
          step: strings.tourStep(tour.index, tour.total),
          isLast: tour.pending.isEmpty,
          onNext: () => ref.read(tourControllerProvider.notifier).next(),
          onSkip: () => ref.read(tourControllerProvider.notifier).skip(),
        ),
      ],
    );
  }

  (String, String) _copyFor(TourStop stop, NexusStrings strings) =>
      switch (stop) {
        TourStop.orb => (strings.tourOrbTitle, strings.tourOrbBody),
        TourStop.composer => (
          strings.tourComposerTitle,
          strings.tourComposerBody,
        ),
        TourStop.dock => (strings.tourDockTitle, strings.tourDockBody),
        TourStop.meter => (strings.tourMeterTitle, strings.tourMeterBody),
      };
}

/// El velo con un hueco: todo oscuro menos la pieza de la que se habla.
class _Spotlight extends CustomPainter {
  const _Spotlight({
    required this.hole,
    required this.scrim,
    required this.ring,
  });

  final Rect hole;
  final Color scrim;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final marco = RRect.fromRectAndRadius(
      hole.inflate(6),
      const Radius.circular(NexusRadius.md),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(marco),
      ),
      Paint()..color = scrim,
    );
    canvas.drawRRect(
      marco,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_Spotlight old) =>
      old.hole != hole || old.scrim != scrim || old.ring != ring;
}

/// La explicación, al lado de la pieza y nunca encima.
class _Card extends StatelessWidget {
  /// Para poder medirla en una prueba: que se calce al texto es justo lo que se
  /// rompió, y no lo detecta ninguna aserción de las normales.
  static const cardKey = ValueKey('tour-card');

  const _Card({
    required this.hole,
    required this.title,
    required this.body,
    required this.step,
    required this.isLast,
    required this.onNext,
    required this.onSkip,
  });

  static const _width = 340.0;
  static const _gap = NexusSpacing.s5;

  /// Lo mínimo para que la tarjeta sea legible en un hueco. Por debajo de esto
  /// no se intenta meterla al lado: se pone encima de la pieza, que es peor de
  /// aspecto pero se puede leer y pulsar.
  static const _minAlto = 200.0;

  final Rect hole;
  final String title;
  final String body;
  final String step;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pantalla = MediaQuery.sizeOf(context);

    // Fuera del hueco si cabe, y si no, encima — pero **siempre dentro de la
    // ventana**.
    //
    // El orbe ocupa el centro entero de la pantalla, así que en su parada no hay
    // hueco ni arriba ni abajo: medido, quedan 123 px por debajo en una ventana
    // de 800, y menos en la mínima de 768. La primera versión ponía la tarjeta
    // «fuera» sin comprobar que cupiera y la echaba 820 px por encima del borde;
    // sus botones no se podían ni pulsar, y de hecho no se podía terminar el tour.
    final espacioAbajo = pantalla.height - hole.bottom - _gap * 2;
    final espacioArriba = hole.top - _gap * 2;

    final double? arriba;
    final double? abajo;
    final double maxAlto;
    if (espacioAbajo >= _minAlto) {
      arriba = hole.bottom + _gap;
      abajo = null;
      maxAlto = espacioAbajo;
    } else if (espacioArriba >= _minAlto) {
      arriba = null;
      abajo = pantalla.height - hole.top + _gap;
      maxAlto = espacioArriba;
    } else {
      // Solapa, que es inevitable, y se va al pie: el orbe es una esfera difusa
      // y tapar su parte de abajo se lee bien, mientras el marco del foco sigue
      // viéndose alrededor.
      arriba = null;
      abajo = _gap;
      maxAlto = pantalla.height - _gap * 2;
    }

    final izquierda = (hole.center.dx - _width / 2).clamp(
      NexusSpacing.s6,
      (pantalla.width - _width - NexusSpacing.s6).clamp(
        NexusSpacing.s6,
        double.infinity,
      ),
    );

    return Positioned(
      left: izquierda,
      top: arriba,
      bottom: abajo,
      width: _width,
      child: ConstrainedBox(
        // El tope de alto no es cosmético: sin él, un texto largo —o una
        // tipografía más ancha— empuja los botones fuera de la ventana y el tour
        // deja de poder cerrarse.
        constraints: BoxConstraints(maxHeight: maxAlto),
        child: Container(
          key: cardKey,
          padding: const EdgeInsets.all(NexusSpacing.s5),
          decoration: BoxDecoration(
            color: colors.deep,
            border: Border.all(color: colors.accent),
            borderRadius: BorderRadius.circular(NexusRadius.md),
          ),
          child: Column(
            // La tarjeta se calza a su texto.
            //
            // Sin esto la columna ocupa **todo** el alto que le deja el tope, y el
            // `Flexible` del cuerpo lo rellena: salían cuadros de casi 800 px con el
            // texto arriba y el resto vacío, cruzando la pantalla por el medio. Con
            // `min`, el `Flexible` solo sirve para lo que se puso — encogerse si no
            // cabe — y no para estirar.
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step,
                style: NexusTypography.label.copyWith(color: colors.faint),
              ),
              const SizedBox(height: NexusSpacing.s3),
              Text(
                title,
                style: NexusTypography.lead.copyWith(color: colors.ink),
              ),
              const SizedBox(height: NexusSpacing.s3),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    body,
                    style: NexusTypography.body.copyWith(color: colors.mute),
                  ),
                ),
              ),
              const SizedBox(height: NexusSpacing.s5),
              // `Expanded` en el de saltar y no `spaceBetween` a secas: con los dos
              // a su tamaño natural la fila **desbordaba 48 px**, y en inglés o con
              // una tipografía más ancha volvería a pasar. Así el que cede es el
              // secundario, que es el que puede ceder.
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      // Saltar está siempre, y no escondido: un tour del que no se
                      // puede salir es un peaje.
                      child: TextButton(
                        onPressed: onSkip,
                        child: Text(
                          context.strings.tourSkip,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NexusTypography.label.copyWith(
                            color: colors.faint,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: NexusSpacing.s3),
                  FilledButton(
                    onPressed: onNext,
                    child: Text(
                      isLast
                          ? context.strings.tourDone
                          : context.strings.tourNext,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

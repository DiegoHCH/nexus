import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/domain/entities/corrida_de_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';
import 'package:nexus/features/e2e/presentation/providers/e2e_providers.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';

/// Las pruebas de la app: las que hay, las que corrieron, y una corriendo.
///
/// **Un sheet y no una sección de Ajustes**, al contrario que los emuladores. La
/// diferencia es la misma que separa el visor de documentos de una preferencia:
/// esto trae algo que acabas de pedir —una prueba que corre ahora— y por eso
/// interrumpe. Un emulador se consulta antes de trabajar; una prueba se mira
/// mientras pasa.
class PruebasSheet extends ConsumerWidget {
  const PruebasSheet({super.key, required this.proyecto});

  final String? proyecto;

  /// Se abre así, como el de documentos.
  static Future<void> open(BuildContext context, {String? proyecto}) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => PruebasSheet(proyecto: proyecto),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final enMarcha = ref.watch(pruebaEnMarchaProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: colors.deep,
        border: Border(top: BorderSide(color: colors.rule)),
      ),
      padding: const EdgeInsets.all(NexusSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.e2eTitle,
            style: NexusTypography.label.copyWith(color: colors.faint),
          ),
          const SizedBox(height: NexusSpacing.s4),

          // **Lo que corre ahora, arriba y sin tener que buscarlo.** Es lo único
          // de esta pantalla que cambia solo, y por eso va primero.
          if (enMarcha != null) ...[
            _EnMarcha(prueba: enMarcha),
            const SizedBox(height: NexusSpacing.s5),
          ],

          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (proyecto case final p?) _Lanzadera(proyecto: p),
                  const SizedBox(height: NexusSpacing.s5),
                  const _Historial(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La prueba que corre, paso a paso.
class _EnMarcha extends ConsumerWidget {
  const _EnMarcha({required this.prueba});

  final PruebaEnMarcha prueba;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final estados = prueba.estados;

    return Container(
      padding: const EdgeInsets.all(NexusSpacing.s4),
      decoration: BoxDecoration(
        color: colors.void_.withValues(alpha: 0.5),
        border: Border.all(color: prueba.viva ? colors.accent : colors.rule),
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (prueba.viva)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colors.accent,
                  ),
                )
              else
                Icon(
                  prueba.fallo ? Icons.close : Icons.check,
                  size: 14,
                  color: prueba.fallo ? colors.err : colors.ok,
                ),
              const SizedBox(width: NexusSpacing.s3),
              Expanded(
                child: Text(
                  prueba.flow,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
              ),
              Text(
                '${prueba.terminados}/${prueba.pasos.length}',
                style: NexusTypography.mono.copyWith(color: colors.faint),
              ),
              if (prueba.viva)
                TextButton(
                  style: _apretado,
                  onPressed: ref.read(pruebaEnMarchaProvider.notifier).parar,
                  child: Text(strings.e2eStop),
                ),
            ],
          ),
          const SizedBox(height: NexusSpacing.s3),

          // **Los pasos del YAML con su símbolo, o la salida en plano.**
          //
          // Se degrada y no miente: si lo ejecutado no cuadra con las líneas del
          // archivo —`runFlow`, un bucle— [PasosDeUnaPrueba.estados] devuelve
          // `null` y aquí se enseña lo que Maestro imprimió, que sigue siendo
          // verdad.
          if (estados == null)
            _Salida(lineas: prueba.lineas)
          else
            for (final (i, paso) in prueba.pasos.indexed)
              _FilaDePaso(texto: paso, estado: estados[i]),
        ],
      ),
    );
  }
}

class _FilaDePaso extends StatelessWidget {
  const _FilaDePaso({required this.texto, required this.estado});

  final String texto;
  final EstadoDePaso estado;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (icono, color) = switch (estado) {
      EstadoDePaso.hecho => (Icons.check, colors.ok),
      EstadoDePaso.enCurso => (Icons.autorenew, colors.accent),
      EstadoDePaso.fallado => (Icons.close, colors.err),
      EstadoDePaso.pendiente => (Icons.remove, colors.rule),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Icon(icono, size: 12, color: color),
          const SizedBox(width: NexusSpacing.s3),
          Expanded(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NexusTypography.mono.copyWith(
                // Lo pendiente en gris y lo hecho legible: la lista se lee de un
                // barrido sin contar iconos.
                color: estado == EstadoDePaso.pendiente
                    ? colors.faint
                    : colors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Salida extends StatelessWidget {
  const _Salida({required this.lineas});

  final List<String> lineas;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxHeight: 160),
    child: SingleChildScrollView(
      reverse: true,
      child: SelectableText(
        lineas.join('\n'),
        style: NexusTypography.mono.copyWith(color: context.colors.faint),
      ),
    ),
  );
}

final _apretado = TextButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s2),
  minimumSize: Size.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.compact,
);

/// Elegir una prueba de este proyecto y lanzarla.
class _Lanzadera extends ConsumerStatefulWidget {
  const _Lanzadera({required this.proyecto});

  final String proyecto;

  @override
  ConsumerState<_Lanzadera> createState() => _LanzaderaState();
}

class _LanzaderaState extends ConsumerState<_Lanzadera> {
  String? _error;

  /// Los dispositivos sobre los que se puede correr: **encendidos y nada más**.
  ///
  /// Un `maestro test --device` contra un emulador apagado falla, así que
  /// ofrecerlo sería ofrecer ese fallo — el mismo criterio que el panel de correr
  /// la app. Para encenderlo está el icono de los dispositivos.
  List<String> get _dispositivos => [
    for (final e in ref.watch(emuladoresProvider).value?.emuladores ?? const [])
      if (e.corriendo && e.deviceId != null) e.deviceId!,
    for (final d in ref.watch(dispositivosProvider).value ?? const []) d.id,
  ];

  Future<void> _lanzar(Prueba prueba) async {
    final dispositivos = _dispositivos;
    if (dispositivos.isEmpty) {
      setState(() => _error = context.strings.e2eNoDevice);
      return;
    }
    setState(() => _error = null);

    final error = await ref
        .read(pruebaEnMarchaProvider.notifier)
        .lanzar(
          prueba: prueba,
          proyecto: widget.proyecto,
          // El primero encendido. Elegir dispositivo es una pregunta más, y para
          // una prueba de humo el que haya sirve; cuando importe, aquí va un
          // selector como el de correr la app.
          deviceId: dispositivos.first,
          perfil: 'local',
        );
    if (!mounted) return;
    if (error != null) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final pruebas = ref.watch(pruebasProvider(widget.proyecto)).value ?? const [];
    final corriendo = ref.watch(pruebaEnMarchaProvider)?.viva ?? false;

    if (pruebas.isEmpty) {
      return Text(
        strings.e2eNone,
        style: NexusTypography.mono.copyWith(color: colors.faint),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final prueba in pruebas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(Icons.description_outlined, size: 13, color: colors.faint),
                const SizedBox(width: NexusSpacing.s3),
                Expanded(
                  child: Text(
                    prueba.nombre,
                    style: NexusTypography.data.copyWith(color: colors.ink),
                  ),
                ),
                TextButton(
                  style: _apretado,
                  onPressed: corriendo ? null : () => _lanzar(prueba),
                  child: Text(strings.e2eRun),
                ),
              ],
            ),
          ),
        if (_error case final mensaje?) ...[
          const SizedBox(height: NexusSpacing.s2),
          Text(
            mensaje,
            style: NexusTypography.mono.copyWith(color: colors.err),
          ),
        ],
      ],
    );
  }
}

/// Lo que ya corrió, agrupado por proyecto.
///
/// Las que no se pudieron atribuir van en su propio grupo y **no se esconden**:
/// no saber de qué proyecto salió una corrida es un problema nuestro, y taparla
/// se lo pasaría al usuario en forma de historial incompleto.
class _Historial extends ConsumerWidget {
  const _Historial();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final corridas = ref.watch(corridasDePruebaProvider);

    final lista = corridas.value;
    if (lista == null) {
      return Text(
        strings.e2eTitle,
        style: NexusTypography.mono.copyWith(color: colors.faint),
      );
    }
    if (lista.isEmpty) {
      return Text(
        strings.e2eNoRuns,
        style: NexusTypography.mono.copyWith(color: colors.faint),
      );
    }

    final porProyecto = <String, List<CorridaDePrueba>>{};
    for (final corrida in lista) {
      porProyecto
          .putIfAbsent(corrida.proyecto ?? '', () => [])
          .add(corrida);
    }
    // Lo sin atribuir al final: es lo menos útil, no lo primero que se mira.
    final claves = porProyecto.keys.toList()
      ..sort((a, b) => a.isEmpty ? 1 : (b.isEmpty ? -1 : a.compareTo(b)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final clave in claves) ...[
          Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.s4, bottom: 4),
            child: Text(
              clave.isEmpty
                  ? strings.e2eUnattributed
                  : clave.split('/').last,
              style: NexusTypography.label.copyWith(color: colors.faint),
            ),
          ),
          for (final corrida in porProyecto[clave]!)
            _FilaDeCorrida(corrida: corrida),
        ],
      ],
    );
  }
}

class _FilaDeCorrida extends ConsumerWidget {
  const _FilaDeCorrida({required this.corrida});

  final CorridaDePrueba corrida;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    final (icono, color, etiqueta) = switch (corrida.comoAcabo) {
      ComoAcabo.bien => (Icons.check, colors.ok, strings.e2ePassed),
      ComoAcabo.mal => (Icons.close, colors.err, strings.e2eFailed),
      ComoAcabo.enMarcha => (
        Icons.autorenew,
        colors.accent,
        strings.e2eRunningNow,
      ),
      ComoAcabo.vayaUstedASaber => (
        Icons.help_outline,
        colors.warn,
        strings.e2eUnknown,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icono, size: 12, color: color),
          const SizedBox(width: NexusSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  corrida.flow,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
                Text(
                  // Cuándo, cómo acabó y cuántos pasos llegaron: «2 de 8» dice
                  // dónde se rompió sin abrir nada.
                  '${_cuando(corrida.cuando)} · $etiqueta · '
                  '${corrida.pasosBien}/${corrida.pasos}',
                  style: NexusTypography.mono.copyWith(color: colors.faint),
                ),
              ],
            ),
          ),
          TextButton(
            style: _apretado,
            onPressed: () async {
              await ref.read(e2eDataSourceProvider).borrar(corrida.carpeta);
              ref.invalidate(corridasDePruebaProvider);
            },
            child: Text(strings.e2eDelete),
          ),
        ],
      ),
    );
  }

  /// La hora si es de hoy, la fecha si no. Un historial de una tarde con la fecha
  /// repetida en cada fila es ruido.
  String _cuando(DateTime cuando) {
    final ahora = DateTime.now();
    final hoy =
        cuando.year == ahora.year &&
        cuando.month == ahora.month &&
        cuando.day == ahora.day;
    final hh = cuando.hour.toString().padLeft(2, '0');
    final mm = cuando.minute.toString().padLeft(2, '0');
    return hoy ? '$hh:$mm' : '${cuando.day}/${cuando.month} $hh:$mm';
  }
}

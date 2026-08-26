import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';
import 'package:nexus/features/run/domain/entities/config_de_arranque.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/domain/usecases/lector_de_configs.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';
import 'package:nexus/features/run/presentation/providers/run_providers.dart';

/// Correr la app: elegir entorno y dispositivo, y gobernarla.
///
/// **En el compositor y no en Ajustes**, por lo mismo que los dispositivos: una
/// app corriendo es estado vivo, no configuración. Y aquí es donde se mira
/// mientras se trabaja.
///
/// El icono cambia de significado según lo que haya: sin nada corriendo es
/// «correr», y con algo corriendo es «esto está pasando» — con su punto, como el
/// de los dispositivos.
class CorrerMenu extends ConsumerWidget {
  const CorrerMenu({super.key, required this.proyecto});

  /// La carpeta de trabajo de esta conversación. `null` si no hay proyecto.
  ///
  /// Las configuraciones son **de este proyecto**: van por aquí y no por una
  /// lista global, porque la de un repo no significa nada en otro.
  final String? proyecto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final corridas = ref.watch(corridasProvider);
    final mia = proyecto == null
        ? <Corrida>[]
        : corridas.values.where((c) => c.proyecto == proyecto).toList();

    return PopupMenuButton<void>(
      color: colors.deep,
      tooltip: '',
      onOpened: () {
        if (proyecto case final p?) ref.invalidate(configsProvider(p));
        ref.invalidate(emuladoresProvider);
        ref.invalidate(dispositivosProvider);
      },
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: SizedBox(
            width: 380,
            child: _Panel(proyecto: proyecto),
          ),
        ),
      ],
      child: Semantics(
        label: strings.runTitle,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.play_arrow_rounded,
                size: 17,
                color: mia.isEmpty ? colors.faint : colors.accent,
              ),
            ),
            if (mia.isNotEmpty)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.void_, width: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends ConsumerStatefulWidget {
  const _Panel({required this.proyecto});

  final String? proyecto;

  @override
  ConsumerState<_Panel> createState() => _PanelState();
}

class _PanelState extends ConsumerState<_Panel> {
  String? _config;
  String? _dispositivo;
  var _ocupado = false;
  String? _error;

  Future<void> _correr() async {
    final proyecto = widget.proyecto;
    final configs = ref.read(configsProvider(proyecto ?? '')).value ?? const [];
    final nombre = _elegida(configs);
    final deviceId = _dispositivo;
    if (proyecto == null || nombre == null || deviceId == null) return;

    final elegida = configs.where((c) => c.nombre == nombre).firstOrNull;
    if (elegida == null) return;

    final (:dispositivo, :plataforma) = _datosDelDispositivo(deviceId);
    if (plataforma == null) return;

    setState(() {
      _ocupado = true;
      _error = null;
    });
    final error = await ref
        .read(corridasProvider.notifier)
        .correr(
          proyecto: proyecto,
          configuracion: nombre,
          args: LectorDeConfigs.argumentos(elegida, proyecto: proyecto),
          deviceId: deviceId,
          dispositivo: dispositivo,
          plataforma: plataforma,
        );
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _error = error;
    });
  }

  /// De dónde sale el nombre y la plataforma de un dispositivo elegido.
  ///
  /// De las dos listas que ya existen: los emuladores arrancados y los teléfonos
  /// enchufados. No hay una tercera fuente porque no debe haberla — sería otra
  /// verdad que mantener.
  ({String dispositivo, PlataformaEmulador? plataforma}) _datosDelDispositivo(
    String deviceId,
  ) {
    for (final e in ref.read(emuladoresProvider).value?.emuladores ?? const []) {
      if (e.deviceId == deviceId) {
        return (dispositivo: e.nombre, plataforma: e.plataforma);
      }
    }
    for (final d in ref.read(dispositivosProvider).value ?? const []) {
      if (d.id == deviceId) {
        return (dispositivo: d.nombre, plataforma: d.plataforma);
      }
    }
    return (dispositivo: deviceId, plataforma: null);
  }

  /// Cuál va puesta: lo elegido en esta sesión, o lo recordado de este proyecto.
  String? _elegida(List<ConfigDeArranque> configs) {
    final nombres = {for (final c in configs) c.nombre};
    if (_config case final elegido? when nombres.contains(elegido)) {
      return elegido;
    }
    final recordado =
        ref.watch(configsPorDefectoProvider)[widget.proyecto ?? ''];
    return recordado != null && nombres.contains(recordado) ? recordado : null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final proyecto = widget.proyecto;

    if (proyecto == null) {
      return Text(
        strings.runNoProject,
        style: NexusTypography.mono.copyWith(color: colors.faint),
      );
    }

    final configs = ref.watch(configsProvider(proyecto)).value ?? const [];
    final corridas = ref
        .watch(corridasProvider)
        .values
        .where((c) => c.proyecto == proyecto)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          strings.runTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s3),

        for (final corrida in corridas) _FilaDeCorrida(corrida: corrida),
        if (corridas.isNotEmpty) const SizedBox(height: NexusSpacing.s4),

        if (configs.isEmpty)
          Text(
            strings.runNoConfigs,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          )
        else ...[
          _Elegir(
            // **La recordada, si sigue existiendo.** Se guarda el nombre y no un
            // índice: los índices bailan al añadir una configuración al
            // `launch.json`, y ese día estarías corriendo otro entorno sin
            // enterarte. Si el nombre ya no está, no se ofrece y hay que elegir.
            valor: _elegida(configs),
            opciones: [for (final c in configs) c.nombre],
            pista: strings.runTitle,
            onElegir: (v) {
              setState(() => _config = v);
              ref
                  .read(configsPorDefectoProvider.notifier)
                  .elegir(proyecto, v);
            },
          ),
          const SizedBox(height: NexusSpacing.s2),
          _Elegir(
            valor: _dispositivo,
            opciones: _dispositivosDisponibles(),
            pista: strings.runChooseDevice,
            onElegir: (v) => setState(() => _dispositivo = v),
          ),
          const SizedBox(height: NexusSpacing.s3),
          Row(
            children: [
              if (_ocupado)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colors.accent,
                  ),
                )
              else
                OutlinedButton(
                  onPressed: _elegida(configs) != null && _dispositivo != null
                      ? _correr
                      : null,
                  child: Text(strings.runStart),
                ),
            ],
          ),
        ],

        if (_error case final mensaje?) ...[
          const SizedBox(height: NexusSpacing.s3),
          Text(
            mensaje,
            style: NexusTypography.mono.copyWith(color: colors.err),
          ),
        ],
      ],
    );
  }

  /// Lo que hay para correr: emuladores **arrancados** y teléfonos enchufados.
  ///
  /// Un emulador apagado no aparece a propósito: `flutter run -d` sobre algo que
  /// no está encendido falla, y ofrecerlo sería ofrecer ese fallo. Para
  /// arrancarlo está el icono de al lado.
  List<String> _dispositivosDisponibles() => [
    for (final e in ref.watch(emuladoresProvider).value?.emuladores ?? const [])
      if (e.corriendo && e.deviceId != null) e.deviceId!,
    for (final d in ref.watch(dispositivosProvider).value ?? const []) d.id,
  ];
}

class _Elegir extends StatelessWidget {
  const _Elegir({
    required this.valor,
    required this.opciones,
    required this.pista,
    required this.onElegir,
  });

  final String? valor;
  final List<String> opciones;
  final String pista;
  final void Function(String) onElegir;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s3),
      decoration: BoxDecoration(
        color: colors.void_.withValues(alpha: 0.5),
        border: Border.all(color: colors.rule),
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valor,
          isExpanded: true,
          isDense: true,
          dropdownColor: colors.deep,
          focusColor: Colors.transparent,
          hint: Text(
            pista,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
          icon: Icon(Icons.expand_more, size: 14, color: colors.faint),
          items: [
            for (final opcion in opciones)
              DropdownMenuItem(
                value: opcion,
                child: Text(
                  opcion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onElegir(v);
          },
        ),
      ),
    );
  }
}

/// Una app corriendo, con lo que se le puede pedir.
class _FilaDeCorrida extends ConsumerWidget {
  const _FilaDeCorrida({required this.corrida});

  final Corrida corrida;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final controller = ref.read(corridasProvider.notifier);

    // Lo que se lee debajo del nombre: si está compilando, **qué** compila; si no,
    // en qué estado anda. El progreso pesa más porque es lo que cambia.
    final detalle = switch (corrida.estado) {
      EstadoDeCorrida.arrancando =>
        corrida.progreso ?? strings.runCompiling,
      EstadoDeCorrida.corriendo => strings.runRunning,
      EstadoDeCorrida.parando => strings.runStopping,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: NexusSpacing.s3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: corrida.estado == EstadoDeCorrida.corriendo
                  ? colors.ok
                  : colors.warn,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  corrida.configuracion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
                Text(
                  '${corrida.dispositivo} · $detalle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.mono.copyWith(color: colors.faint),
                ),
              ],
            ),
          ),
          // **Recargar solo cuando se puede.** Antes de `app.started` no hay a
          // quién pedírselo, y un botón que contesta «todavía está compilando» es
          // un botón que no debía estar encendido.
          if (corrida.puedeRecargar) ...[
            _BotonMini(
              icono: Icons.refresh,
              titulo: strings.runReload,
              onPulsar: () =>
                  controller.recargar(deviceId: corrida.deviceId),
            ),
            _BotonMini(
              icono: Icons.restart_alt,
              titulo: strings.runRestart,
              onPulsar: () => controller.recargar(
                deviceId: corrida.deviceId,
                completa: true,
              ),
            ),
          ],
          if (corrida.estado != EstadoDeCorrida.parando)
            _BotonMini(
              icono: Icons.stop_rounded,
              titulo: strings.runStop,
              onPulsar: () => controller.parar(corrida.deviceId),
            ),
        ],
      ),
    );
  }
}

/// Una acción sobre la corrida: icono con su nombre en el tooltip.
///
/// **Iconos y no palabras, y eso lo decidió una prueba**: «Recargar»,
/// «Reiniciar» y «Parar» en la misma fila desbordaban el panel por 71 px, con el
/// nombre del entorno al lado. Con tres acciones no hay ancho que alcance, y
/// esconder una detrás de un menú sería peor: son las tres que se usan.
///
/// El nombre no se pierde, se mueve al tooltip — y ahí sigue estando para quien
/// use un lector de pantalla, porque `IconButton` lo anuncia.
class _BotonMini extends StatelessWidget {
  const _BotonMini({
    required this.icono,
    required this.titulo,
    required this.onPulsar,
  });

  final IconData icono;
  final String titulo;
  final VoidCallback onPulsar;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPulsar,
    tooltip: titulo,
    iconSize: 15,
    splashRadius: 14,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    constraints: const BoxConstraints(),
    visualDensity: VisualDensity.compact,
    color: context.colors.faint,
    icon: Icon(icono),
  );
}

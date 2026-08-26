import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';

/// Los emuladores de la máquina: cuáles hay, cuáles están arriba, y el botón.
///
/// **Sección de Ajustes y no un sheet sobre el orbe**, y la diferencia no es
/// estética: el visor de documentos interrumpe porque trae algo que acabas de
/// pedir, y esto se consulta *antes* de trabajar. Configuración, no noticia.
class EmuladoresSection extends ConsumerStatefulWidget {
  const EmuladoresSection({super.key});

  @override
  ConsumerState<EmuladoresSection> createState() => _EmuladoresSectionState();
}

class _EmuladoresSectionState extends ConsumerState<EmuladoresSection> {
  /// Cuál se está moviendo, para que solo su fila se apague.
  ///
  /// Por id y no un booleano de toda la sección: arrancar tarda, y bloquear la
  /// lista entera impediría cerrar otro mientras uno arranca.
  String? _ocupado;
  String? _error;

  Future<void> _lanzar(Emulador emulador, {bool frio = false}) async {
    setState(() {
      _ocupado = emulador.id;
      _error = null;
    });
    final error = await ref
        .read(emuladoresDataSourceProvider)
        .lanzar(emulador, frio: frio);
    ref.invalidate(emuladoresProvider);
    if (!mounted) return;
    setState(() {
      _ocupado = null;
      _error = error;
    });
  }

  Future<void> _cerrar(Emulador emulador) async {
    setState(() {
      _ocupado = emulador.id;
      _error = null;
    });
    final error = await ref.read(emuladoresDataSourceProvider).cerrar(emulador);
    ref.invalidate(emuladoresProvider);
    if (!mounted) return;
    setState(() {
      _ocupado = null;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final lista = ref.watch(emuladoresProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.emulatorsTitle,
                style: NexusTypography.label.copyWith(color: colors.faint),
              ),
            ),
            OutlinedButton(
              onPressed: _ocupado != null
                  ? null
                  : () => ref.invalidate(emuladoresProvider),
              child: Text(strings.emulatorsRefresh),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.emulatorsExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),

        switch (lista) {
          AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // El error de la herramienta va **arriba y literal**: «No se
              // encontró Flutter…» dice qué hacer, y taparlo con un «no se pudo»
              // obliga a abrir la terminal para averiguarlo.
              if (value.error case final mensaje?)
                Text(
                  mensaje,
                  style: NexusTypography.mono.copyWith(color: colors.err),
                )
              else if (value.emuladores.isEmpty)
                Text(
                  strings.emulatorsEmpty,
                  style: NexusTypography.mono.copyWith(color: colors.faint),
                )
              else
                for (final emulador in value.emuladores)
                  _FilaDeEmulador(
                    emulador: emulador,
                    ocupado: _ocupado == emulador.id,
                    apagado: _ocupado != null,
                    onLanzar: () => _lanzar(emulador),
                    onLanzarEnFrio: () => _lanzar(emulador, frio: true),
                    onCerrar: () => _cerrar(emulador),
                  ),

              // **Los teléfonos de verdad, en su propio grupo y sin botón.**
              //
              // Aparte porque el verbo no es el mismo: un emulador se arranca y
              // se cierra, y uno de estos ya está — lo único que se puede hacer
              // con él es usarlo. Mezclarlos en la misma lista obligaría a poner
              // un botón apagado en la mitad de las filas, que es enseñar un
              // control que nunca sirve.
              //
              // Y sí valen, aunque no tengan botón: son la respuesta a «¿sobre
              // qué puedo correr esto?», y el id que llevan debajo es el que pide
              // `-d`.
              if (value.dispositivos.isNotEmpty) ...[
                const SizedBox(height: NexusSpacing.s5),
                Text(
                  strings.emulatorsConnected,
                  style: NexusTypography.label.copyWith(color: colors.faint),
                ),
                const SizedBox(height: NexusSpacing.s2),
                for (final dispositivo in value.dispositivos)
                  _FilaDeDispositivo(dispositivo: dispositivo),
              ],
            ],
          ),
          AsyncError() => Text(
            strings.emulatorsEmpty,
            style: NexusTypography.mono.copyWith(color: colors.warn),
          ),
          _ => Text(
            strings.emulatorsRefresh,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
        },

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
}

/// Un teléfono enchufado. Sin botón a propósito: ver [_FilaDeEmulador] arriba.
class _FilaDeDispositivo extends StatelessWidget {
  const _FilaDeDispositivo({required this.dispositivo});

  final DispositivoConectado dispositivo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // El punto va siempre encendido: si está en la lista, está enchufado.
          // No hay estado intermedio que enseñar.
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: NexusSpacing.s3),
            decoration: BoxDecoration(shape: BoxShape.circle, color: colors.ok),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dispositivo.nombre,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
                Text(
                  // El id detrás porque es lo que hace falta para `-d`, y en
                  // Android el nombre es el código de modelo —`24069PC21G`— que
                  // no dice nada por sí solo.
                  '${dispositivo.plataforma.name} · ${dispositivo.id}',
                  style: NexusTypography.mono.copyWith(color: colors.faint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaDeEmulador extends StatelessWidget {
  const _FilaDeEmulador({
    required this.emulador,
    required this.ocupado,
    required this.apagado,
    required this.onLanzar,
    required this.onLanzarEnFrio,
    required this.onCerrar,
  });

  final Emulador emulador;
  final bool ocupado;
  final bool apagado;
  final VoidCallback onLanzar;
  final VoidCallback onLanzarEnFrio;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final puede = !apagado;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // El punto de estado antes del nombre: se lee de un barrido, sin
          // tener que llegar al botón para saber cuál está vivo.
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: NexusSpacing.s3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: emulador.corriendo ? colors.ok : colors.rule,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  emulador.nombre,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
                Text(
                  emulador.corriendo
                      ? '${emulador.plataforma.name} · ${strings.emulatorsRunning}'
                      : emulador.plataforma.name,
                  style: NexusTypography.mono.copyWith(color: colors.faint),
                ),
              ],
            ),
          ),
          // **El botón dice «cerrar» cuando ya está arriba**, en vez de ofrecer
          // arrancar algo que corre. Arrancar dos veces el mismo no duplica
          // nada, pero el botón estaría mintiendo sobre lo que va a hacer.
          if (ocupado)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colors.accent,
              ),
            )
          else if (emulador.corriendo)
            TextButton(
              onPressed: puede ? onCerrar : null,
              child: Text(strings.emulatorsClose),
            )
          else ...[
            // El arranque en frío solo existe en Android; en iOS no se ofrece
            // para no poner un botón que no hace nada distinto.
            if (emulador.plataforma == PlataformaEmulador.android)
              TextButton(
                onPressed: puede ? onLanzarEnFrio : null,
                child: Text(
                  strings.emulatorsColdBoot,
                  style: NexusTypography.mono.copyWith(color: colors.faint),
                ),
              ),
            TextButton(
              onPressed: puede ? onLanzar : null,
              child: Text(strings.emulatorsLaunch),
            ),
          ],
        ],
      ),
    );
  }
}

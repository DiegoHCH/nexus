import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Lo que abre `⌘Y`: las conversaciones guardadas, **por perfil**.
///
/// Arriba, una pestaña por cuenta —`work`, `private`— y dentro las suyas, de
/// todos los proyectos de esa cuenta. Es la organización que ya tiene el vault
/// en el disco (`perfil/proyecto/conversación`), y repetirla aquí es lo que
/// hace que buscar en la app y buscar en Obsidian se sientan como lo mismo.
///
/// Las pestañas salen de lo que haya: si solo se ha trabajado con una cuenta,
/// hay una pestaña, y no se dibujan casillas vacías para las que faltan.
class ConversationHistorySheet extends ConsumerStatefulWidget {
  const ConversationHistorySheet({
    super.key,
    required this.onPick,
    required this.onForget,
    this.forgetFolder,
  });

  final void Function(ConversationSummary record) onPick;
  final VoidCallback onForget;

  /// La carpeta cuya sesión de Claude se olvidaría, o `null` si no hay ninguna
  /// conversación abierta.
  ///
  /// Va con nombre y apellido porque el botón hacía otra cosa de la que
  /// parecía: no borra nada de esta lista —para eso está la papelera de cada
  /// fila—, sino que hace que **Claude olvide el hilo** de esa carpeta y el
  /// siguiente encargo empiece sin contexto arrastrado. Con la ventana
  /// enseñando conversaciones de varias cuentas y proyectos, un «empezar de
  /// cero» a secas no decía sobre cuál.
  final String? forgetFolder;

  static Future<void> open(
    BuildContext context, {
    required void Function(ConversationSummary record) onPick,
    required VoidCallback onForget,
    String? forgetFolder,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ConversationHistorySheet(
        onPick: onPick,
        onForget: onForget,
        forgetFolder: forgetFolder,
      ),
    );
  }

  @override
  ConsumerState<ConversationHistorySheet> createState() =>
      _ConversationHistorySheetState();
}

class _ConversationHistorySheetState
    extends ConsumerState<ConversationHistorySheet> {
  /// Se guarda el **nombre** del perfil y no su posición: la lista se recarga
  /// mientras la ventana está abierta, y un índice apuntaría a otra pestaña.
  String? _profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final saved = ref.watch(allSavedConversationsProvider);

    return Dialog(
      backgroundColor: colors.rise,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.rule2),
        borderRadius: BorderRadius.circular(NexusRadius.md),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(NexusSpacing.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.history,
                style: NexusTypography.label.copyWith(color: colors.accent),
              ),
              const SizedBox(height: NexusSpacing.s2),
              Text(
                strings.historyExplainer,
                style: NexusTypography.mono.copyWith(color: colors.faint),
              ),
              const SizedBox(height: NexusSpacing.s5),
              Flexible(
                child: saved.when(
                  loading: () => const SizedBox.shrink(),
                  // Que falle leer no es «no hay historial»: son cosas muy
                  // distintas para quien busca algo que sabe que estaba ahí.
                  error: (error, _) => Text(
                    '$error',
                    style: NexusTypography.mono.copyWith(color: colors.err),
                  ),
                  data: _body,
                ),
              ),
              if (widget.forgetFolder case final folder?) ...[
                const SizedBox(height: NexusSpacing.s5),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onForget();
                  },
                  child: Text(strings.startFromScratchIn(folder)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(List<ConversationSummary> records) {
    final colors = context.colors;
    if (records.isEmpty) {
      return Text(
        context.strings.nothingAskedYet,
        style: NexusTypography.mono.copyWith(color: colors.faint),
      );
    }

    final byProfile = <String, List<ConversationSummary>>{};
    for (final record in records) {
      final profile = record.profileName?.trim();
      byProfile
          .putIfAbsent(
            profile == null || profile.isEmpty
                ? context.strings.claudeAccountDefault
                : profile,
            () => [],
          )
          .add(record);
    }

    // Las pestañas son para separar cuentas, así que **solo existen si hay más
    // de una configurada en el Mac**. Con una sola, dividir en pestañas es
    // inventar una frontera donde no la hay — y aun así podían salir dos, si
    // algunas conversaciones venían de antes de que existieran los perfiles.
    final cuentas = ref.watch(claudeProfilesProvider).value ?? const [];
    final agrupa = cuentas.length > 1;
    final profiles = agrupa ? (byProfile.keys.toList()..sort()) : <String>[];
    final current = byProfile.containsKey(_profile)
        ? _profile!
        : (profiles.isEmpty ? '' : profiles.first);
    final visibles = agrupa ? byProfile[current]! : records;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Con una sola cuenta no se dibuja la fila de pestañas: una pestaña
        // suelta no organiza nada, solo ocupa sitio.
        if (agrupa && profiles.length > 1)
          Row(
            children: [
              for (final profile in profiles)
                // Repartidas a partes iguales: son hermanas, y con el ancho
                // pegado al texto la de nombre más largo parecía la principal.
                Expanded(
                  child: _Tab(
                    label: profile,
                    count: byProfile[profile]!.length,
                    active: profile == current,
                    onTap: () => setState(() => _profile = profile),
                  ),
                ),
            ],
          ),
        const SizedBox(height: NexusSpacing.s4),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: visibles.length,
            itemBuilder: (context, index) {
              final record = visibles[index];
              return _Row(
                record: record,
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onPick(record);
                },
                onDelete: () => ref.read(deleteConversationProvider)(record),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.s4,
          vertical: NexusSpacing.s3,
        ),
        decoration: BoxDecoration(
          // Subrayado y no relleno: la pestaña activa se marca sin que la fila
          // parezca un botón pulsado.
          border: Border(
            bottom: BorderSide(
              color: active ? colors.accent : colors.rule,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label.toUpperCase(),
              style: NexusTypography.label.copyWith(
                color: active ? colors.accent : colors.faint,
              ),
            ),
            const SizedBox(width: NexusSpacing.s2),
            Text(
              '$count',
              style: NexusTypography.data.copyWith(color: colors.faint),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.record,
    required this.onTap,
    required this.onDelete,
  });

  final ConversationSummary record;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  /// Borrar pide confirmación **en la propia fila**, no en otro diálogo encima
  /// de este: lo que se va a borrar es esta línea, y verla mientras decides es
  /// más claro que un cuadro que repite el título.
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final onTap = widget.onTap;
    final colors = context.colors;
    final when = record.startedAt;
    String two(int value) => value.toString().padLeft(2, '0');

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.rule)),
        ),
        padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // La fecha delante y en monoespaciada: así las columnas cuadran y
            // la lista se recorre con la vista en vertical.
            Text(
              '${when.year}-${two(when.month)}-${two(when.day)} ${two(when.hour)}:${two(when.minute)}',
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
            const SizedBox(width: NexusSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NexusTypography.body.copyWith(color: colors.ink),
                  ),
                  // El proyecto va debajo porque dentro de un perfil hay
                  // varios, y sin esto dos conversaciones de repos distintos
                  // se ven idénticas.
                  Text(
                    record.projectName,
                    style: NexusTypography.mono.copyWith(color: colors.faint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NexusSpacing.s3),
            // Los turnos, cuando constan. Una nota escrita por una versión
            // anterior no los lleva en la cabecera, y ahí se prefiere no decir
            // nada a decir cero: cero mensajes es una conversación que no se
            // habría guardado.
            if (record.turns > 0) ...[
              Text(
                '${record.turns}',
                style: NexusTypography.data.copyWith(color: colors.faint),
              ),
              const SizedBox(width: NexusSpacing.s3),
            ],
            if (_confirming) ...[
              TextButton(
                onPressed: () => setState(() => _confirming = false),
                child: Text(
                  context.strings.cancel,
                  style: NexusTypography.label.copyWith(color: colors.faint),
                ),
              ),
              TextButton(
                onPressed: widget.onDelete,
                child: Text(
                  context.strings.deleteForReal,
                  style: NexusTypography.label.copyWith(color: colors.err),
                ),
              ),
            ] else
              IconButton(
                onPressed: () => setState(() => _confirming = true),
                tooltip: context.strings.deleteConversation,
                iconSize: 14,
                splashRadius: 14,
                icon: Icon(Icons.delete_outline, color: colors.faint),
              ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/artifacts/presentation/widgets/artifacts_sheet.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/workspace/data/datasources/plan_firmado_data_source.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/presentation/providers/plan_firmado_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/workspace/presentation/widgets/firmar_plan_sheet.dart';

/// Las fichas de la barra: carpeta, modelo, esfuerzo, cupo.
///
/// Aparte desde que `composer_bar.dart` pasó de las 1.100 líneas. Es la pieza más
/// grande del compositor —233 líneas ella sola— y la que menos tiene que ver con
/// escribir: son estado de la conversación puesto donde se lee de un vistazo.

/// Dónde estás, en fila: carpeta, repositorio, rama, cuenta y si se le puede
/// hablar a este proyecto.
///
/// La carpeta **se puede cambiar desde aquí**: antes, sin ninguna emparejada,
/// esto era una etiqueta que decía que no había carpeta y no hacía nada — un
/// cartel en el sitio donde uno va a arreglarlo.
class ComposerChips extends ConsumerWidget {
  const ComposerChips({super.key, required this.folder, this.folderPath});

  final PairedFolder? folder;

  /// La carpeta de **esta** conversación, emparejada o no. Hace falta aparte
  /// porque «sin proyecto» trabaja sobre la carpeta de documentos, que no está
  /// emparejada y por tanto no aparece como `PairedFolder`.
  final String? folderPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final workspace = ref.watch(workspaceControllerProvider);
    final paired = folder;
    // «Sin proyecto»: se trabaja en la carpeta de documentos. No es un modo
    // aparte con reglas propias —sería otra cosa que mantener—, es una carpeta
    // más, la que ya elegiste para lo que sale de las conversaciones.
    final documentos = ref.watch(artifactsFolderProvider);
    final suelta = folderPath != null && folderPath == documentos;
    // La rama es la del sitio donde va a trabajar Claude, que con una raíz de
    // varios repos no es la carpeta emparejada sino el repo elegido.
    final git = paired == null
        ? null
        : ref.watch(gitInfoProvider(paired.workingDirectory)).value;
    final repos = paired == null
        ? const <String>[]
        : ref.watch(reposInsideProvider(paired.path)).value ?? const [];

    return Row(
      children: [
        PopupMenuButton<String>(
          color: colors.deep,
          tooltip: '',
          onSelected: (value) async {
            if (value == '__pair__') {
              await ref.read(workspaceControllerProvider.notifier).pairFolder();
              return;
            }
            if (value == '__loose__') {
              // Sin carpeta de documentos todavía no hay dónde trabajar, así
              // que se abre justo la ventana donde se elige, en vez de un
              // aviso que manda a buscarla.
              if (documentos == null) {
                await ArtifactsSheet.open(context);
                return;
              }
              value = documentos;
            }
            final abierta = ref.read(conversationsProvider).focused;
            if (abierta == null) {
              // Sin ninguna abierta no se crea nada: se apunta la carpeta y la
              // conversación nacerá cuando escribas o hables. Crear una aquí
              // llenaría el dock de conversaciones vacías cada vez que miras
              // dónde ibas a trabajar.
              //
              // Lo que sí tiene que valer es **esa** carpeta y no otra: la que
              // se apunte aquí es la que se usa al escribir.
              await ref
                  .read(workspaceControllerProvider.notifier)
                  .setActive(value);
              return;
            }

            final dicho = ref
                .read(assistantControllerProvider(abierta.id))
                .messages
                .isEmpty;
            if (dicho) {
              // Vacía: se mueve, y con ella su nombre en el dock. Es corregir
              // el rumbo antes de empezar, no empezar otra cosa.
              await ref
                  .read(conversationsProvider.notifier)
                  .moveTo(abierta.id, value);
            } else {
              // Con algo hablado, la nueva carpeta merece su propia
              // conversación: la de al lado tiene la memoria de la suya.
              await ref.read(conversationsProvider.notifier).open(value);
            }
          },
          itemBuilder: (context) => [
            for (final option in workspace.folders)
              PopupMenuItem<String>(
                value: option.path,
                child: Row(
                  children: [
                    Text(
                      option.name,
                      style: NexusTypography.data.copyWith(color: colors.ink),
                    ),
                    if (option.path == paired?.path) ...[
                      const SizedBox(width: NexusSpacing.s3),
                      Icon(Icons.check, size: 13, color: colors.accent),
                    ],
                  ],
                ),
              ),
            PopupMenuItem<String>(
              value: '__loose__',
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 14,
                    color: colors.faint,
                  ),
                  const SizedBox(width: NexusSpacing.s3),
                  Text(
                    strings.noProject,
                    style: NexusTypography.data.copyWith(color: colors.mute),
                  ),
                  if (suelta) ...[
                    const SizedBox(width: NexusSpacing.s3),
                    Icon(Icons.check, size: 13, color: colors.accent),
                  ],
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: '__pair__',
              child: Row(
                children: [
                  Icon(
                    Icons.create_new_folder_outlined,
                    size: 14,
                    color: colors.faint,
                  ),
                  const SizedBox(width: NexusSpacing.s3),
                  Text(
                    strings.addFolderShort,
                    style: NexusTypography.data.copyWith(color: colors.mute),
                  ),
                ],
              ),
            ),
          ],
          child: _Chip(
            icon: suelta
                ? Icons.auto_awesome_outlined
                : paired == null
                ? Icons.folder_off_outlined
                : Icons.folder_outlined,
            label: suelta
                ? strings.noProject
                : paired?.name ?? strings.chooseFolder,
            // Sin proyecto no es un aviso: es una elección legítima, y pintarla
            // en ámbar la haría parecer un estado a medio arreglar.
            warn: paired == null && !suelta,
          ),
        ),
        // Con varios repos dentro, el chip elige. Es el caso de una carpeta
        // raíz de trabajo: Claude tiene que arrancar **dentro** del repo o
        // cualquier cosa de git ocurre en el sitio equivocado.
        if (repos.length > 1 && paired != null)
          PopupMenuButton<String?>(
            color: colors.deep,
            tooltip: '',
            onSelected: (value) => ref
                .read(workspaceControllerProvider.notifier)
                .setActiveRepo(paired.path, value),
            itemBuilder: (context) => [
              PopupMenuItem<String?>(
                child: Row(
                  children: [
                    Text(
                      // Trabajar sobre la raíz sigue siendo válido: hay
                      // encargos que cruzan repos y ahí bajar a uno sería
                      // esconderle la mitad.
                      paired.name,
                      style: NexusTypography.data.copyWith(color: colors.mute),
                    ),
                    if (paired.activeRepo == null) ...[
                      const SizedBox(width: NexusSpacing.s3),
                      Icon(Icons.check, size: 13, color: colors.accent),
                    ],
                  ],
                ),
              ),
              for (final repo in repos)
                PopupMenuItem<String?>(
                  value: repo,
                  child: Row(
                    children: [
                      Text(
                        repo.split('/').last,
                        style: NexusTypography.data.copyWith(color: colors.ink),
                      ),
                      if (repo == paired.activeRepo) ...[
                        const SizedBox(width: NexusSpacing.s3),
                        Icon(Icons.check, size: 13, color: colors.accent),
                      ],
                    ],
                  ),
                ),
            ],
            child: _Chip(
              icon: Icons.hub_outlined,
              label: git?.repository ?? paired.name,
            ),
          )
        else if (git != null) ...[
          // El repositorio aparte de la carpeta porque no siempre coinciden: se
          // puede trabajar sobre un subdirectorio de un repo, y entonces la
          // carpeta dice una cosa y el repo otra.
          _Chip(icon: Icons.hub_outlined, label: git.repository),
        ],
        if (git?.branch case final branch?)
          _Chip(icon: Icons.alt_route, label: branch),
        if (git == null && paired != null)
          // Sin repositorio no hay nada que deshacer, y eso hay que decirlo
          // donde se ve el permiso: es la red de seguridad que falta.
          _Chip(
            icon: Icons.warning_amber,
            label: strings.noGitRepo,
            warn: true,
          ),
        // La cuenta solo se enseña si hay más de una en el Mac: con una sola,
        // decir cuál se usa es contestar una pregunta que nadie tiene.
        if (ref.watch(claudeProfilesProvider).value case final cuentas?)
          if (cuentas.length > 1)
            if (paired?.claudeProfile?.split('/').last case final profile?)
              if (profile.startsWith('.claude-'))
                _Chip(icon: Icons.badge_outlined, label: profile.substring(8)),
        // El plan, **solo donde se exige**. En las demás carpetas no aparece
        // nada: un chip apagado en todas las conversaciones enseñaría un
        // mecanismo que casi nadie enciende, y el sitio se paga en atención.
        if (folderPath case final carpeta?)
          if (ref
                  .watch(
                    planFirmadoProvider(
                      dondeMirar(
                        carpeta: carpeta,
                        perfil: paired?.claudeProfile,
                      ),
                    ),
                  )
                  .value
              case final plan? when plan.exige)
            _PlanChip(
              plan: plan,
              donde: dondeMirar(
                carpeta: carpeta,
                perfil: paired?.claudeProfile,
              ),
            ),
        // La modalidad de voz no se repite aquí: se decide por carpeta en
        // Ajustes, y tenerla también en la barra creaba dos sitios que decían
        // lo mismo con distinta forma —uno como estado, el otro como
        // interruptor— y se contradecían a la vista.
      ],
    );
  }
}

/// El plan de esta carpeta: firmado y con lo que le queda, o sin firmar en ámbar.
///
/// **No apaga el botón de mandar**, y es a propósito: el gate solo deniega escrituras, así
/// que sin plan el asistente sigue pudiendo leer el proyecto y contestar preguntas —que es
/// buena parte de para qué se usa—. Apagar el compositor prohibiría más de lo que prohíbe
/// el hook, y una app más estricta que su propia regla se acaba desactivando entera.
///
/// Se refresca solo porque **la vigencia se mide con el reloj**: un chip que dijera «47
/// MIN» durante dos horas es exactamente la mentira que este mecanismo existe para no
/// contar. Solo hay temporizador donde hay plan, que son las pocas carpetas que lo piden.
class _PlanChip extends StatefulWidget {
  const _PlanChip({required this.plan, required this.donde});

  final PlanFirmado plan;
  final DondeMirar donde;

  @override
  State<_PlanChip> createState() => _PlanChipState();
}

class _PlanChipState extends State<_PlanChip> {
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    // Medio minuto: se enseñan minutos, así que más fino sería trabajo que no se ve.
    _reloj = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final ahora = DateTime.now().toUtc();
    final vigente = widget.plan.vigenteEn(ahora);
    final resta = widget.plan.restanteEn(ahora);

    return Tooltip(
      message: widget.plan.plan ?? '',
      child: GestureDetector(
        onTap: () => FirmarPlanSheet.open(context, widget.donde),
        child: _Chip(
          icon: vigente ? Icons.assignment_turned_in_outlined : Icons.gavel,
          label: vigente
              ? strings.planValidFor((resta?.inMinutes ?? 0) + 1)
              : strings.planUnsigned,
          warn: !vigente,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.warn = false});

  final IconData icon;
  final String label;

  /// Algo que falta o que conviene mirar: sin carpeta, sin git.
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: NexusSpacing.s3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(
            color: warn ? colors.warn.withValues(alpha: 0.5) : colors.rule,
          ),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: warn ? colors.warn : colors.faint),
            const SizedBox(width: 6),
            Text(
              label,
              style: NexusTypography.mono.copyWith(
                color: warn ? colors.warn : colors.mute,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

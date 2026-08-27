import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/presentation/providers/e2e_providers.dart';
import 'package:nexus/features/e2e/presentation/providers/raiz_de_los_flows_provider.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Dónde viven las pruebas de cada proyecto, y cuáles hay.
///
/// **Una sección propia y no un campo en Permisos.** Ahí estaba y no se encontraba: un
/// permiso es lo que Claude puede hacer, y esto es dónde vive un archivo. Y sobre todo,
/// en Permisos solo se veía la carpeta activa — la pregunta que trae a alguien aquí es
/// «¿qué pruebas tengo?», que es de todos los proyectos a la vez.
class PruebasSection extends ConsumerStatefulWidget {
  const PruebasSection({super.key});

  @override
  ConsumerState<PruebasSection> createState() => _PruebasSectionState();
}

class _PruebasSectionState extends ConsumerState<PruebasSection> {
  final _raiz = TextEditingController();
  var _cargada = false;

  @override
  void dispose() {
    _raiz.dispose();
    super.dispose();
  }

  String get _home => Platform.environment['HOME'] ?? '';

  /// Con `~` cuando cae en el home: es como se lee, y así el ajuste sobrevive a que la
  /// cuenta del Mac se llame de otra forma.
  String _corta(String ruta) => _home.isNotEmpty && ruta.startsWith(_home)
      ? '~${ruta.substring(_home.length)}'
      : ruta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final raiz = ref.watch(raizDeLosFlowsProvider);
    final carpetas = ref.watch(workspaceControllerProvider).folders;

    // La caja arranca con lo guardado, y solo la primera vez: sobrescribirla en cada
    // dibujo pisaría lo que se está escribiendo.
    if (!_cargada && raiz != null) {
      _cargada = true;
      _raiz.text = raiz;
    }

    return ListView(
      children: [
        Text(
          strings.flowsRootExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s4),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('raiz-de-las-pruebas'),
                controller: _raiz,
                style: NexusTypography.mono.copyWith(color: colors.ink),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: strings.flowsRootHint,
                  hintStyle: NexusTypography.mono.copyWith(color: colors.rule2),
                ),
                onChanged: (valor) =>
                    ref.read(raizDeLosFlowsProvider.notifier).elegir(valor),
              ),
            ),
            const SizedBox(width: NexusSpacing.s3),
            TextButton(
              key: const ValueKey('elegir-raiz-de-pruebas'),
              onPressed: () async {
                final elegida = await ref
                    .read(folderPickerProvider)
                    .pickFolder();
                if (elegida == null) return;
                final conTilde = _corta(elegida);
                _raiz.text = conTilde;
                await ref
                    .read(raizDeLosFlowsProvider.notifier)
                    .elegir(conTilde);
              },
              child: Text(
                strings.testsFolderPick,
                style: NexusTypography.label.copyWith(color: colors.accent),
              ),
            ),
          ],
        ),

        const SizedBox(height: NexusSpacing.s6),
        Text(
          strings.flowsByProject,
          style: NexusTypography.label.copyWith(color: colors.accent),
        ),
        const SizedBox(height: NexusSpacing.s3),
        if (carpetas.isEmpty)
          Text(
            strings.flowsNoProjects,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          )
        else
          for (final carpeta in carpetas)
            _Proyecto(carpeta: carpeta, raiz: raiz, home: _home),
      ],
    );
  }
}

/// Un proyecto: dónde caen sus pruebas y cuáles hay.
class _Proyecto extends ConsumerWidget {
  const _Proyecto({
    required this.carpeta,
    required this.raiz,
    required this.home,
  });

  final PairedFolder carpeta;
  final String? raiz;
  final String home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final donde = carpeta.pruebasEn(home, raiz: raiz);
    final pruebas =
        ref.watch(pruebasProvider(carpeta.workingDirectory)).value ?? const [];
    final corta = home.isNotEmpty && donde.startsWith(home)
        ? '~${donde.substring(home.length)}'
        : donde;

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  carpeta.nombreDelRepo,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
              ),
              Text(
                pruebas.isEmpty
                    ? strings.flowsNoneHere
                    : strings.flowsCount(pruebas.length),
                style: NexusTypography.label.copyWith(
                  color: pruebas.isEmpty ? colors.faint : colors.mute,
                ),
              ),
            ],
          ),
          // La ruta ya resuelta y no lo que se escribió: es donde se ve que la raíz le
          // pone el nombre del proyecto detrás, y que un repo que declara la suya la
          // conserva. Sin esto hay que adivinar cuál de las tres reglas ganó.
          Text(
            corta,
            style: NexusTypography.mono.copyWith(color: colors.rule2),
          ),
          for (final prueba in pruebas)
            Padding(
              padding: const EdgeInsets.only(
                left: NexusSpacing.s4,
                top: NexusSpacing.s2,
              ),
              child: Text(
                prueba.nombre,
                style: NexusTypography.mono.copyWith(color: colors.faint),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/superpowers/domain/entities/skill.dart';
import 'package:nexus/features/superpowers/domain/usecases/skill_source.dart';
import 'package:nexus/features/superpowers/presentation/providers/superpowers_providers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nexus/features/superpowers/domain/usecases/fallos_por_cuenta.dart';

/// Las skills de una cuenta: las puestas, las de un repo, y crear una propia.
class SkillsPanel extends ConsumerStatefulWidget {
  const SkillsPanel({
    super.key,
    required this.configDir,
    this.tambienEn = const [],
  });

  final String configDir;

  /// Las demás cuentas donde replicar lo que se instale aquí.
  ///
  /// Vacío es lo normal: solo la de arriba. Va como lista y no como un booleano «en
  /// todas» porque este panel no sabe cuántas cuentas hay ni cómo se llaman — eso lo
  /// decide la sección, que es quien tiene las pestañas.
  final List<String> tambienEn;

  @override
  ConsumerState<SkillsPanel> createState() => _SkillsPanelState();
}

class _SkillsPanelState extends ConsumerState<SkillsPanel> {
  final _repo = TextEditingController(text: SkillSource.officialRepo);
  final _newName = TextEditingController();
  final _search = TextEditingController();

  /// Cuántas del repo se enseñan de una vez, y con qué se filtran.
  ///
  /// Hace falta desde que el escáner deja de recortar a 100: hay repos con
  /// **cientos** —`davila7/claude-code-templates` tiene 896— y una lista sin
  /// buscador ahí no sirve de nada. Es la misma solución que ya usan los
  /// plugins con sus 287, y por el mismo motivo: lo que queda fuera se dice,
  /// no se recorta en silencio.
  static const _shown = 20;
  var _query = '';

  /// El repo que se está mirando. Aparte de lo escrito en la caja para que
  /// teclear no dispare un clon por letra.
  var _browsing = SkillSource.officialRepo;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _repo.dispose();
    _newName.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Filtra por nombre **y por descripción**: la descripción es lo único que el
  /// agente lee para decidir si activarse, así que buscar «flutter» tiene que
  /// encontrar la que se llama `mobile-design` y lo menciona dentro.
  List<Skill> _filtrar(List<Skill> skills) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return skills;
    return skills
        .where(
          (skill) =>
              skill.id.toLowerCase().contains(q) ||
              skill.description.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _act(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await action();
    ref.invalidate(installedSkillsProvider(widget.configDir));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _create() async {
    final name = _newName.text;
    if (name.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(skillsDataSourceProvider)
        .create(widget.configDir, name: name, description: '');
    ref.invalidate(installedSkillsProvider(widget.configDir));
    // Se abre lo recién creado: una skill vacía no sirve de nada, y el paso
    // siguiente —escribir cuándo usarla— es siempre el mismo.
    if (result.path case final path?) {
      await launchUrl(Uri.file(path));
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
      if (result.error == null) _newName.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final installed =
        ref.watch(installedSkillsProvider(widget.configDir)).value ?? const [];
    final ids = installed.map((skill) => skill.id).toSet();
    final catalog = ref.watch(repoSkillsProvider(_browsing));

    return ListView(
      children: [
        Text(
          strings.skillsExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),

        _Heading(strings.skillsInstalled),
        if (installed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
            child: Text(
              strings.skillsNone,
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
          ),
        for (final skill in installed)
          _SkillRow(
            skill: skill,
            trailing: IconButton(
              onPressed: _busy
                  ? null
                  : () => _act(
                      () => ref
                          .read(skillsDataSourceProvider)
                          .remove(widget.configDir, skill.id),
                    ),
              icon: Icon(Icons.close, size: 14, color: colors.faint),
              splashRadius: 14,
              tooltip: strings.skillsRemove,
            ),
          ),

        const SizedBox(height: NexusSpacing.s6),
        _Heading(strings.skillsFromRepo),
        Row(
          children: [
            Expanded(
              child: _Field(controller: _repo, hint: 'usuario/repo'),
            ),
            const SizedBox(width: NexusSpacing.s3),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _browsing = _repo.text.trim()),
              child: Text(strings.skillsBrowse),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s3),
        switch (catalog) {
          AsyncData(:final value) when value.error != null => Text(
            value.error!,
            style: NexusTypography.mono.copyWith(color: colors.err),
          ),
          AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // El total va en la cabecera y el buscador debajo: con cientos de
              // skills, enseñar veinte sin decir cuántas hay se lee como «esto
              // es todo lo que trae el repo».
              _Heading(strings.skillsCatalog(value.skills.length)),
              _Field(
                controller: _search,
                hint: strings.skillsSearchHint,
                onChanged: (texto) => setState(() => _query = texto),
              ),
              const SizedBox(height: NexusSpacing.s3),
              for (final skill in _filtrar(value.skills).take(_shown))
                _SkillRow(
                  skill: skill,
                  dimmed: ids.contains(skill.id),
                  trailing: IconButton(
                    onPressed: _busy
                        ? null
                        : () => _act(
                            () => ref
                                .read(skillsDataSourceProvider)
                                // A la cuenta de arriba **y a las demás si se
                                // pidió**: una skill en un solo perfil es invisible
                                // para las carpetas del otro, también para sus
                                // encargos.
                                .installEn(
                                  [widget.configDir, ...widget.tambienEn],
                                  repoRaw: _browsing,
                                  id: skill.id,
                                )
                                .then(FallosPorCuenta.primero),
                          ),
                    // Ya instalada se ofrece **actualizar**, no se apaga el
                    // botón: un repo de skills cambia, y la copia local es de
                    // cuando se instaló.
                    icon: Icon(
                      ids.contains(skill.id) ? Icons.refresh : Icons.add,
                      size: 15,
                      color: colors.accent,
                    ),
                    splashRadius: 14,
                    tooltip: ids.contains(skill.id)
                        ? strings.skillsUpdate
                        : strings.skillsInstall,
                  ),
                ),
              if (_filtrar(value.skills).length > _shown)
                Padding(
                  padding: const EdgeInsets.only(top: NexusSpacing.s2),
                  child: Text(
                    strings.skillsMore(_filtrar(value.skills).length - _shown),
                    style: NexusTypography.mono.copyWith(color: colors.faint),
                  ),
                ),
            ],
          ),
          AsyncError() => Text(
            strings.skillsRepoFailed,
            style: NexusTypography.mono.copyWith(color: colors.err),
          ),
          _ => Text(
            strings.skillsFetching,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
        },

        const SizedBox(height: NexusSpacing.s6),
        _Heading(strings.skillsOwn),
        Row(
          children: [
            Expanded(
              child: _Field(controller: _newName, hint: strings.skillsOwnHint),
            ),
            const SizedBox(width: NexusSpacing.s3),
            OutlinedButton(
              onPressed: _busy ? null : _create,
              child: Text(strings.skillsCreate),
            ),
          ],
        ),
        if (_error case final message?) ...[
          const SizedBox(height: NexusSpacing.s3),
          Text(
            message,
            style: NexusTypography.mono.copyWith(color: colors.err),
          ),
        ],
      ],
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({
    required this.skill,
    required this.trailing,
    this.dimmed = false,
  });

  final Skill skill;
  final Widget trailing;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                skill.id,
                style: NexusTypography.data.copyWith(
                  color: dimmed ? colors.faint : colors.ink,
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              // Dos líneas y no una: la descripción es **lo único** que el
              // agente lee para decidir si activa la skill, así que quien elige
              // necesita verla, no adivinarla por el nombre.
              child: Text(
                skill.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NexusTypography.mono.copyWith(color: colors.faint),
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: NexusSpacing.s2),
    child: Text(
      text,
      style: NexusTypography.label.copyWith(color: context.colors.accent),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, this.onChanged});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: NexusTypography.mono.copyWith(color: colors.ink),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: NexusTypography.mono.copyWith(color: colors.rule2),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.s3,
          vertical: NexusSpacing.s3,
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.rule),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.accent),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
      ),
    );
  }
}

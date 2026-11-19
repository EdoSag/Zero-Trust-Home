import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/device_adapter.dart';
import '../data/home_store.dart';
import '../l10n/l10n.dart';
import '../model/scene.dart';
import 'common.dart';
import 'scene_page.dart';

void openScene(BuildContext context, [Scene? scene]) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => ScenePage(scene: scene)));

/// The home's scenes as a row of chips: a tap runs one, touch and hold
/// changes it.
class SceneRow extends ConsumerStatefulWidget {
  const SceneRow({super.key});

  @override
  ConsumerState<SceneRow> createState() => _SceneRowState();
}

class _SceneRowState extends ConsumerState<SceneRow> {
  final _running = <String>{};

  Future<void> _run(Scene scene) async {
    if (!_running.add(scene.id)) return;
    setState(() {});
    final l = context.l10n;
    final failed = await ref.read(deviceControlProvider).runScene(scene);
    if (!mounted) return;
    setState(() => _running.remove(scene.id));
    showSnack(
      context,
      failed.isEmpty
          ? l.sceneDone(scene.name)
          : l.sceneFailed(
              scene.name,
              [for (final d in failed) d.name].join(', '),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scenes = ref.watch(currentScenesProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          for (final s in scenes) ...[
            GestureDetector(
              onLongPress: () => openScene(context, s),
              child: ActionChip(
                avatar: _running.contains(s.id)
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                label: Text(s.name),
                onPressed: () => _run(s),
              ),
            ),
            const SizedBox(width: 8),
          ],
          ActionChip(
            avatar: const Icon(Icons.add),
            label: Text(scenes.isEmpty ? l.addScene : l.newScene),
            onPressed: () => openScene(context),
          ),
        ],
      ),
    );
  }
}

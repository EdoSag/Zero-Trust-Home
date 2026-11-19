import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/device_adapter.dart';
import '../data/home_store.dart';
import '../l10n/l10n.dart';
import '../model/device.dart';
import '../model/scene.dart';
import 'common.dart';
import 'device_controls.dart';

/// Makes or changes a scene: a name, and what it does with each device.
class ScenePage extends ConsumerStatefulWidget {
  const ScenePage({super.key, this.scene});

  /// Null for a new scene.
  final Scene? scene;

  @override
  ConsumerState<ScenePage> createState() => _ScenePageState();
}

class _ScenePageState extends ConsumerState<ScenePage> {
  late final _name = TextEditingController(text: widget.scene?.name ?? '');
  final _picks = <String, ScenePick>{};
  var _filled = false;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The devices a scene can do something with.
  List<HomeDevice> _devices() => [
    for (final d in ref.read(currentDevicesProvider))
      if (sceneChoices(d).length > 1) d,
  ];

  ScenePick _pick(HomeDevice d) => _picks[d.id] ?? ScenePick.skip;

  void _copyNow() {
    setState(() {
      for (final d in _devices()) {
        final state = ref.read(deviceStateProvider(d.id)).value;
        _picks[d.id] = state == null || !state.reachable
            ? ScenePick.skip
            : scenePickFrom(d, state.values);
      }
    });
  }

  Future<void> _save() async {
    final l = context.l10n;
    final name = _name.text.trim();
    if (name.isEmpty) return showSnack(context, l.sceneNeedsName);
    final actions = [for (final d in _devices()) ...sceneActions(d, _pick(d))];
    if (actions.isEmpty) return showSnack(context, l.sceneNeedsDevice);
    final home = ref.read(currentHomeProvider);
    if (home == null) return;
    setState(() => _saving = true);
    final repo = ref.read(homeRepositoryProvider);
    final old = widget.scene;
    if (old == null) {
      await repo.addScene(home.id, name, actions);
      // Shown on the home page once this one closes.
      if (mounted) showSnack(context, l.sceneEditHint);
    } else {
      await repo.saveScene(old.copyWith(name: name, actions: actions));
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete(Scene scene) async {
    final l = context.l10n;
    final ok = await confirm(
      context,
      title: l.deleteSceneTitle(scene.name),
      body: l.deleteSceneBody,
      action: l.delete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(homeRepositoryProvider).removeScene(scene.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Keeps the device list current while the page is open.
    ref.watch(currentDevicesProvider);
    final devices = _devices();
    final scene = widget.scene;
    if (!_filled && scene != null) {
      _filled = true;
      for (final d in devices) {
        _picks[d.id] = scenePickOf(d, scene);
      }
    }
    final rooms = {for (final r in ref.watch(currentRoomsProvider)) r.id: r};

    return Scaffold(
      appBar: AppBar(
        title: Text(scene == null ? l.newScene : l.editScene),
        actions: [
          if (scene != null)
            IconButton(
              tooltip: l.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(scene),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l.sceneName,
              hintText: l.sceneNameHint,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              icon: const Icon(Icons.content_copy_outlined),
              label: Text(l.sceneCopyNow),
              onPressed: _copyNow,
            ),
          ),
          const SizedBox(height: 8),
          for (final d in devices)
            _DeviceChoice(
              key: ValueKey(d.id),
              device: d,
              room: rooms[d.roomId]?.name,
              pick: _pick(d),
              onChanged: (p) => setState(() => _picks[d.id] = p),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: Text(l.save)),
        ],
      ),
    );
  }
}

String sceneChoiceName(AppL10n l, SceneChoice c) => switch (c) {
  SceneChoice.skip => l.sceneDontChange,
  SceneChoice.on => l.stateOn,
  SceneChoice.off => l.stateOff,
  SceneChoice.open => l.stateOpen,
  SceneChoice.closed => l.stateClosed,
  SceneChoice.part => l.scenePartOpen,
  SceneChoice.lock => l.lock,
  SceneChoice.heat => l.sceneSetTemperature,
};

/// One device in the editor: what the scene does with it, and how far.
class _DeviceChoice extends StatelessWidget {
  const _DeviceChoice({
    super.key,
    required this.device,
    required this.room,
    required this.pick,
    required this.onChanged,
  });
  final HomeDevice device;
  final String? room;
  final ScenePick pick;
  final ValueChanged<ScenePick> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final levelOf = sceneLevelOf(device, pick.choice);
    final level = levelOf == null
        ? null
        : (pick.level ?? sceneDefaultLevel(levelOf));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 16),
                Icon(
                  deviceIcon(device.type),
                  color: pick.choice == SceneChoice.skip
                      ? scheme.onSurfaceVariant
                      : scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.name, overflow: TextOverflow.ellipsis),
                      if (room != null)
                        Text(
                          room!,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<SceneChoice>(
                    key: ValueKey('choice-${device.id}'),
                    value: pick.choice,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final c in sceneChoices(device))
                        DropdownMenuItem(
                          value: c,
                          child: Text(
                            sceneChoiceName(l, c),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (c) {
                      if (c != null) onChanged(ScenePick(c, pick.level));
                    },
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
            if (levelOf == Capability.targetTemperature)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: l.colder,
                    icon: const Icon(Icons.remove),
                    onPressed: level! <= 5
                        ? null
                        : () => onChanged(ScenePick(pick.choice, level - 0.5)),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      l.degrees(formatNumber(level)),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: l.warmer,
                    icon: const Icon(Icons.add),
                    onPressed: level >= 35
                        ? null
                        : () => onChanged(ScenePick(pick.choice, level + 0.5)),
                  ),
                ],
              )
            else if (levelOf != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: level!.toDouble().clamp(1, 100),
                        min: 1,
                        max: 100,
                        divisions: 99,
                        semanticFormatterCallback: (x) =>
                            '${levelName(l, levelOf)} ${l.percent(x.round())}',
                        onChanged: (x) =>
                            onChanged(ScenePick(pick.choice, x.round())),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        l.percent(level.round()),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            if (device.capabilities.contains(Capability.locked))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l.sceneNoUnlock,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String levelName(AppL10n l, Capability c) => switch (c) {
  Capability.fanSpeed => l.fanSpeed,
  Capability.position => l.position,
  _ => l.brightness,
};

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/home_store.dart';
import '../l10n/l10n.dart';
import '../model/home.dart';
import 'common.dart';

/// Names a new home and picks its first rooms. Pops when the home is made,
/// which then becomes the one on screen.
class SetupHomePage extends ConsumerStatefulWidget {
  const SetupHomePage({super.key});

  @override
  ConsumerState<SetupHomePage> createState() => _SetupHomePageState();
}

class _SetupHomePageState extends ConsumerState<SetupHomePage> {
  /// Offered as chips; "other" rooms are added later, by name.
  static const _offered = [
    RoomKind.living,
    RoomKind.kitchen,
    RoomKind.bedroom,
    RoomKind.bathroom,
    RoomKind.office,
    RoomKind.kids,
    RoomKind.hallway,
    RoomKind.balcony,
    RoomKind.garden,
    RoomKind.garage,
  ];

  final _name = TextEditingController();
  final _picked = <RoomKind>{
    RoomKind.living,
    RoomKind.kitchen,
    RoomKind.bedroom,
  };
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_saving) return;
    setState(() => _saving = true);
    final l = context.l10n;
    final name = _name.text.trim();
    try {
      final home = await ref
          .read(homeRepositoryProvider)
          .createHome(name.isEmpty ? l.defaultHomeName : name, [
            for (final kind in _offered)
              if (_picked.contains(kind))
                (name: roomKindName(l, kind), kind: kind),
          ]);
      await ref.read(selectedHomeIdProvider.notifier).select(home.id);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.setupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.setupBody, style: t.bodyMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: l.homeName,
              hintText: l.defaultHomeName,
              counterText: '',
            ),
          ),
          const SizedBox(height: 24),
          Text(l.pickRooms, style: t.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final kind in _offered)
                FilterChip(
                  avatar: Icon(roomIcon(kind), size: 18),
                  label: Text(roomKindName(l, kind)),
                  selected: _picked.contains(kind),
                  showCheckmark: false,
                  onSelected: (on) => setState(
                    () => on ? _picked.add(kind) : _picked.remove(kind),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : _create,
            child: Text(l.createHome),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/challenge/achievements.dart';
import '../../core/challenge/challenge_widget_sync.dart';
import '../../core/vocab/checkin_store.dart';

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  static const _store = AchievementStore();

  List<AchievementProgress> _progress = const [];
  List<String> _pinned = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final progress = await _store.progress();
    final pinned = await _store.loadPinned();
    if (!mounted) {
      return;
    }
    setState(() {
      _progress = progress;
      _pinned = pinned;
      _loading = false;
    });
  }

  Future<void> _togglePin(String id) async {
    final before = _pinned.length;
    final next = await _store.togglePinned(id);
    if (!mounted) {
      return;
    }
    if (next.length == before && !next.contains(id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多选择 3 个成就展示在小组件')),
      );
      return;
    }
    setState(() => _pinned = next);
    await ChallengeWidgetSync.sync();
    await const CheckinStore().syncWidget();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('成就')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  '最多选择 3 个成就展示在打卡与段位小组件。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                for (final item in _progress)
                  _AchievementTile(
                    item: item,
                    pinned: _pinned.contains(item.def.id),
                    onTogglePin: () => _togglePin(item.def.id),
                  ),
              ],
            ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({
    required this.item,
    required this.pinned,
    required this.onTogglePin,
  });

  final AchievementProgress item;
  final bool pinned;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final def = item.def;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Opacity(
          opacity: item.unlocked ? 1 : 0.35,
          child: Text(def.emoji, style: const TextStyle(fontSize: 26)),
        ),
        title: Text(
          def.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          def.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: IconButton(
          tooltip: pinned ? '取消展示' : '展示在小组件',
          onPressed: onTogglePin,
          icon: Icon(
            pinned ? Icons.push_pin : Icons.push_pin_outlined,
            color: pinned ? theme.colorScheme.primary : null,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '达成条件：${def.condition}',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: item.ratio,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                item.progressLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                item.unlocked ? '已达成' : '未达成',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: item.unlocked
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

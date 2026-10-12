import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';
import '../utils/responsive.dart';
import '../widgets/ui/ui.dart';

class LeaderboardEntry {
  final String id;
  final String name;
  final int score;
  final String rank;
  final int position;
  final String? avatarUrl;
  final bool isCurrentUser;

  LeaderboardEntry({
    required this.id,
    required this.name,
    required this.score,
    required this.rank,
    required this.position,
    this.avatarUrl,
    this.isCurrentUser = false,
  });
}

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final _supabase = SupabaseService.instance;
  List<LeaderboardEntry> _leaderboardData = [];
  bool _isLoading = true;
  bool _isOffline = false;
  int? _userRank;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    setState(() {
      _isLoading = true;
      _isOffline = false;
    });

    final isOnline = await ConnectivityService.instance.checkConnectivity();
    if (!mounted) return;
    if (!isOnline) {
      setState(() {
        _isLoading = false;
        _isOffline = true;
      });
      return;
    }

    try {
      final data = await _supabase.getLeaderboard(limit: 50);
      final userId = _supabase.userId;
      if (!mounted) return;

      setState(() {
        _leaderboardData = data.map((e) {
          final isMe = e['user_id'] == userId;
          if (isMe) _userRank = (e['rank_position'] as num).toInt();

          return LeaderboardEntry(
            id: e['user_id'] ?? '',
            name: e['display_name'] ?? 'Anonymous',
            score: (e['total_points'] as num?)?.toInt() ?? 0,
            rank: e['rank'] ?? 'Rookie',
            position: (e['rank_position'] as num?)?.toInt() ?? 0,
            avatarUrl: e['avatar_url'],
            isCurrentUser: isMe,
          );
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isOffline = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: 'Leaderboard',
        subtitle: 'Compete with fellow reviewers',
        actions: [
          ToolbarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            size: 40,
            onPressed: _isLoading ? null : _loadLeaderboard,
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingView(label: 'Loading rankings...')
          : _isOffline
              ? Center(
                  child: EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: "Can't load the leaderboard",
                    message: 'Check your internet connection, then try again.',
                    actionLabel: 'Try again',
                    onAction: _loadLeaderboard,
                    color: context.palette.warning,
                  ),
                )
              : LeaderboardView(
                  entries: _leaderboardData,
                  userRank: _userRank,
                  onRefresh: _loadLeaderboard,
                ),
    );
  }
}

/// The rankings themselves: your-rank card, podium and list. Separate
/// from the screen so it can be shown with any list of entries.
class LeaderboardView extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final int? userRank;
  final Future<void> Function() onRefresh;

  const LeaderboardView({
    super.key,
    required this.entries,
    required this.userRank,
    required this.onRefresh,
  });

  static const _medals = [Color(0xFFE5B021), Color(0xFFA7B1C2), Color(0xFFCD8445)];

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    if (entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            EmptyState(
              icon: Icons.leaderboard_rounded,
              title: 'No rankings yet',
              message: 'Complete quizzes to appear on the leaderboard!',
              actionLabel: 'Start reviewing',
              onAction: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }

    final showPodium = entries.length >= 3;
    final rest = showPodium ? entries.skip(3).toList() : entries;
    LeaderboardEntry? me;
    for (final e in entries) {
      if (e.isCurrentUser) me = e;
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(padding, 4, padding, 28),
        children: [
          if (me != null && userRank != null) ...[
            ContentWidth(child: _buildMyRank(context, me)),
            const SizedBox(height: 20),
          ],
          if (showPodium) ...[
            ContentWidth(child: _buildPodium(context, entries.take(3).toList())),
            const SizedBox(height: 20),
          ],
          if (rest.isNotEmpty)
            ContentWidth(
              child: AppCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (var i = 0; i < rest.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 70),
                          child: Divider(height: 1, color: context.palette.border),
                        ),
                      _buildRankingItem(context, rest[i], rest[i].position == 0 ? (showPodium ? i + 4 : i + 1) : rest[i].position),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMyRank(BuildContext context, LeaderboardEntry me) {
    final text = context.textStyles;
    return GradientCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          UserAvatar(
            name: me.name,
            imageUrl: me.avatarUrl,
            size: 48,
            background: Colors.white.withValues(alpha: 0.18),
            foreground: Colors.white,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR RANK',
                  style: text.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 2),
                Text(
                  '#$userRank · ${me.score} pts',
                  style: text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Pill(
            label: me.rank,
            color: Colors.white,
            background: Colors.white.withValues(alpha: 0.16),
          ),
        ],
      ),
    );
  }

  Widget _buildPodium(BuildContext context, List<LeaderboardEntry> top3) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _buildPodiumItem(context, top3[1], 2, 70)),
          const SizedBox(width: 8),
          Expanded(child: _buildPodiumItem(context, top3[0], 1, 96)),
          const SizedBox(width: 8),
          Expanded(child: _buildPodiumItem(context, top3[2], 3, 54)),
        ],
      ),
    );
  }

  Widget _buildPodiumItem(BuildContext context, LeaderboardEntry entry, int rank, double height) {
    final p = context.palette;
    final text = context.textStyles;
    final color = _medals[rank - 1];
    final size = rank == 1 ? 64.0 : 52.0;

    return Column(
      children: [
        if (rank == 1)
          Icon(Icons.workspace_premium_rounded, color: color, size: 26)
        else
          const SizedBox(height: 26),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2.5)),
          child: UserAvatar(name: entry.name, imageUrl: entry.avatarUrl, size: size, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          entry.isCurrentUser ? 'You' : entry.name,
          style: text.titleSmall?.copyWith(color: entry.isCurrentUser ? p.primary : p.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        Text('${entry.score} pts', style: text.labelMedium),
        const SizedBox(height: 10),
        Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0.10)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          alignment: Alignment.center,
          child: Text(
            '$rank',
            style: text.headlineMedium?.copyWith(
              color: Color.lerp(color, Colors.black, context.isDarkMode ? 0 : 0.25),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRankingItem(BuildContext context, LeaderboardEntry entry, int rank) {
    final p = context.palette;
    final text = context.textStyles;
    final medal = rank <= 3 ? _medals[rank - 1] : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: entry.isCurrentUser ? p.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpace.radiusMd),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(
                color: medal ?? (entry.isCurrentUser ? p.primary : p.textTertiary),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          UserAvatar(
            name: entry.name,
            imageUrl: entry.avatarUrl,
            size: 40,
            color: entry.isCurrentUser ? p.primary : AppColors.subjectColor(
              AppColors.subjectColors.keys.elementAt(entry.name.hashCode.abs() % AppColors.subjectColors.length),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isCurrentUser ? 'You' : entry.name,
                  style: text.titleSmall?.copyWith(color: entry.isCurrentUser ? p.onPrimarySoft : p.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Pill(label: entry.rank, color: _getRankColor(context, entry.rank), fontSize: 10.5),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.score}',
                style: text.titleMedium?.copyWith(
                  color: entry.isCurrentUser ? p.primary : p.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text('pts', style: text.labelSmall),
            ],
          ),
        ],
      ),
    );
  }

  Color _getRankColor(BuildContext context, String rank) {
    final p = context.palette;
    switch (rank.toLowerCase()) {
      case 'legend':
        return p.gold;
      case 'master':
        return p.primary;
      case 'expert':
        return p.success;
      case 'advanced':
        return p.info;
      case 'intermediate':
        return const Color(0xFF7C4DDB);
      default:
        return p.textSecondary;
    }
  }
}

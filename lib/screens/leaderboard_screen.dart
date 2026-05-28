import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/theme_service.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';

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
      setState(() {
        _isLoading = false;
        _isOffline = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _isOffline
                ? _buildOfflineState(isDark)
                : RefreshIndicator(
                    onRefresh: _loadLeaderboard,
                    child: _leaderboardData.isEmpty
                        ? _buildEmptyState(isDark)
                        : Column(
                            children: [
                              _buildHeader(isDark),
                              const SizedBox(height: 16),
                              if (_leaderboardData.length >= 3) _buildTopThree(isDark),
                              const SizedBox(height: 16),
                              Expanded(child: _buildRankingsList(isDark)),
                            ],
                          ),
                  ),
      ),
    );
  }
  
  Widget _buildOfflineState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 64,
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'You\'re Offline',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect to the internet to view the leaderboard',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadLeaderboard,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.leaderboard_rounded,
            size: 80,
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No rankings yet',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete quizzes to appear on the leaderboard!',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              'Start Reviewing',
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.arrow_back_ios_rounded,
                color: isDark ? Colors.white70 : Colors.black54,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leaderboard',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Compete with fellow reviewers',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (_userRank != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events_rounded, color: AppColors.accent, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '#$_userRank',
                    style: GoogleFonts.poppins(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopThree(bool isDark) {
    final top3 = _leaderboardData.take(3).toList();
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [

          _buildPodiumItem(top3[1], 2, isDark, 80),
          const SizedBox(width: 12),

          _buildPodiumItem(top3[0], 1, isDark, 100),
          const SizedBox(width: 12),

          _buildPodiumItem(top3[2], 3, isDark, 70),
        ],
      ),
    );
  }

  Widget _buildPodiumItem(LeaderboardEntry entry, int rank, bool isDark, double height) {
    final colors = [
      const Color(0xFFFFD700), // Gold
      const Color(0xFFC0C0C0), // Silver
      const Color(0xFFCD7F32), // Bronze
    ];
    final color = colors[rank - 1];
    final displayName = entry.name.length > 10 ? '${entry.name.substring(0, 8)}...' : entry.name;
    
    return Expanded(
      child: Column(
        children: [

          Container(
            width: rank == 1 ? 64 : 52,
            height: rank == 1 ? 64 : 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.2),
              border: Border.all(color: color, width: 3),
              image: entry.avatarUrl != null ? DecorationImage(
                image: NetworkImage(entry.avatarUrl!),
                fit: BoxFit.cover,
              ) : null,
            ),
            child: entry.avatarUrl == null ? Center(
              child: Text(
                entry.name.isNotEmpty ? entry.name[0].toUpperCase() : '?',
                style: GoogleFonts.poppins(
                  fontSize: rank == 1 ? 24 : 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ) : null,
          ),
          const SizedBox(height: 8),

          Text(
            displayName,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),

          Text(
            '${entry.score}',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            height: height,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.emoji_events_rounded,
                    color: color,
                    size: rank == 1 ? 32 : 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '#$rank',
                    style: GoogleFonts.poppins(
                      fontSize: rank == 1 ? 18 : 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingsList(bool isDark) {
    if (_leaderboardData.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.people_outline_rounded,
                size: 48,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                'No other players yet',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: _leaderboardData.length,
          itemBuilder: (context, index) {
            final entry = _leaderboardData[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _buildRankingItem(entry, index + 1, isDark),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRankBadge(int rank, bool isDark, bool isCurrentUser) {
    // Medal colors for top 3
    if (rank == 1) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '1st',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );
    } else if (rank == 2) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE8E8E8), Color(0xFFA8A8A8)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFC0C0C0).withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '2nd',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF4A4A4A),
            ),
          ),
        ),
      );
    } else if (rank == 3) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFCD7F32), Color(0xFFB8620D)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFCD7F32).withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '3rd',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    
    // Regular rank number for 4th and beyond
    return SizedBox(
      width: 36,
      child: Text(
        '$rank',
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isCurrentUser 
              ? AppColors.accent 
              : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
        ),
      ),
    );
  }

  Widget _buildRankingItem(LeaderboardEntry entry, int rank, bool isDark) {
    final isTop3 = rank <= 3;
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: entry.isCurrentUser 
            ? AppColors.accent.withOpacity(0.1)
            : (isTop3 ? (isDark ? Colors.white.withOpacity(0.03) : Colors.grey.shade50) : Colors.transparent),
        borderRadius: BorderRadius.circular(14),
        border: isTop3 ? Border.all(
          color: rank == 1 
              ? const Color(0xFFFFD700).withOpacity(0.3)
              : rank == 2 
                  ? const Color(0xFFC0C0C0).withOpacity(0.3)
                  : const Color(0xFFCD7F32).withOpacity(0.3),
          width: 1,
        ) : null,
      ),
      child: Row(
        children: [
          _buildRankBadge(rank, isDark, entry.isCurrentUser),
          const SizedBox(width: 14),

          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: entry.isCurrentUser 
                  ? AppColors.accent.withOpacity(0.15)
                  : (isDark ? Colors.white10 : Colors.grey.shade100),
              border: isTop3 ? Border.all(
                color: rank == 1 
                    ? const Color(0xFFFFD700)
                    : rank == 2 
                        ? const Color(0xFFC0C0C0)
                        : const Color(0xFFCD7F32),
                width: 2,
              ) : null,
              image: entry.avatarUrl != null ? DecorationImage(
                image: NetworkImage(entry.avatarUrl!),
                fit: BoxFit.cover,
              ) : null,
            ),
            child: entry.avatarUrl == null ? Center(
              child: Text(
                entry.name.isNotEmpty ? entry.name[0].toUpperCase() : '?',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: entry.isCurrentUser 
                      ? AppColors.accent 
                      : (isDark ? Colors.white70 : Colors.grey.shade600),
                ),
              ),
            ) : null,
          ),
          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isCurrentUser ? 'You' : entry.name,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: entry.isCurrentUser || isTop3 ? FontWeight.w700 : FontWeight.w500,
                    color: entry.isCurrentUser 
                        ? AppColors.accent 
                        : (isDark ? Colors.white : const Color(0xFF1A1A2E)),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _getRankColor(entry.rank).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    entry.rank,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _getRankColor(entry.rank),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.score}',
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: entry.isCurrentUser 
                      ? AppColors.accent 
                      : (isDark ? Colors.white : const Color(0xFF1A1A2E)),
                ),
              ),
              Text(
                'pts',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getRankColor(String rank) {
    switch (rank.toLowerCase()) {
      case 'legend':
        return const Color(0xFFFFD700);
      case 'master':
        return AppColors.accent;
      case 'expert':
        return const Color(0xFF4CAF50);
      case 'advanced':
        return const Color(0xFF2196F3);
      case 'intermediate':
        return const Color(0xFF9C27B0);
      default:
        return Colors.grey;
    }
  }
}

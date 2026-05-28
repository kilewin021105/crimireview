import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';
import '../services/offline_sync_service.dart';

/// A small indicator widget that shows sync status
/// Shows when offline or when there are pending sync operations
class SyncStatusIndicator extends StatelessWidget {
  final bool showLabel;
  final double size;
  
  const SyncStatusIndicator({
    super.key,
    this.showLabel = true,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<ConnectivityService, OfflineSyncService>(
      builder: (context, connectivity, syncService, child) {
        final isOnline = connectivity.isOnline;
        final hasPending = syncService.hasPendingSync;
        final isSyncing = syncService.isSyncing;
        final pendingCount = syncService.pendingCount;
        
        // Don't show anything if online and no pending items
        if (isOnline && !hasPending && !isSyncing) {
          return const SizedBox.shrink();
        }
        
        final isDark = Theme.of(context).brightness == Brightness.dark;
        
        Color bgColor;
        Color iconColor;
        IconData icon;
        String label;
        
        if (!isOnline) {
          // Offline state
          bgColor = Colors.orange.withValues(alpha: 0.15);
          iconColor = Colors.orange;
          icon = Icons.cloud_off_rounded;
          label = hasPending ? 'Offline ($pendingCount pending)' : 'Offline';
        } else if (isSyncing) {
          // Currently syncing
          bgColor = Colors.blue.withValues(alpha: 0.15);
          iconColor = Colors.blue;
          icon = Icons.sync_rounded;
          label = 'Syncing...';
        } else if (hasPending) {
          // Online but has pending items (shouldn't happen normally)
          bgColor = Colors.amber.withValues(alpha: 0.15);
          iconColor = Colors.amber;
          icon = Icons.cloud_upload_rounded;
          label = 'Syncing $pendingCount items';
        } else {
          return const SizedBox.shrink();
        }
        
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: showLabel ? 12 : 8,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              isSyncing
                  ? SizedBox(
                      width: size,
                      height: size,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(iconColor),
                      ),
                    )
                  : Icon(icon, size: size, color: iconColor),
              if (showLabel) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: iconColor,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A banner widget that shows at the top of screens when offline
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityService>(
      builder: (context, connectivity, child) {
        if (connectivity.isOnline) {
          return const SizedBox.shrink();
        }
        
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.orange.shade600,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Consumer<OfflineSyncService>(
                builder: (context, syncService, child) {
                  final pendingCount = syncService.pendingCount;
                  return Text(
                    pendingCount > 0
                        ? 'Offline - $pendingCount items will sync when online'
                        : 'You\'re offline - Progress is saved locally',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

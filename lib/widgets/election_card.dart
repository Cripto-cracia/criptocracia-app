import 'package:flutter/material.dart';
import '../models/election.dart';
import '../generated/app_localizations.dart';

class ElectionCard extends StatefulWidget {
  final Election election;
  final VoidCallback? onTap;

  const ElectionCard({super.key, required this.election, this.onTap});

  @override
  State<ElectionCard> createState() => _ElectionCardState();
}

class _ElectionCardState extends State<ElectionCard> 
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Material(
          elevation: 4,
          shadowColor: colorScheme.shadow.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.surface,
                  colorScheme.surface.withValues(alpha: 0.8),
                ],
              ),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: InkWell(
              onTap: widget.onTap,
              onTapDown: (_) {
                _animationController.forward();
              },
              onTapUp: (_) {
                _animationController.reverse();
              },
              onTapCancel: () {
                _animationController.reverse();
              },
              borderRadius: BorderRadius.circular(16),
              splashColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              highlightColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
              child: Semantics(
                label: _buildSemanticLabel(),
                hint: 'Tap to view election details',
                button: true,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.election.name,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildTimeRemaining(context),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildStatusBadge(context),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(context),
                      const SizedBox(height: 12),
                      _buildProgressIndicator(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final (color, label, icon) = _getStatusInfo(context);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  (Color, String, IconData) _getStatusInfo(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    switch (widget.election.status.toLowerCase()) {
      case 'open':
        return (Colors.orange.shade600, 
                AppLocalizations.of(context).statusOpen, 
                Icons.schedule_outlined);
      case 'in-progress':
        return (Colors.green.shade600, 
                AppLocalizations.of(context).statusInProgress, 
                Icons.radio_button_checked);
      case 'finished':
        return (Colors.blue.shade600, 
                AppLocalizations.of(context).statusFinished, 
                Icons.check_circle_outline);
      case 'canceled':
        return (Colors.red.shade600, 
                AppLocalizations.of(context).statusCanceled, 
                Icons.cancel_outlined);
      default:
        return (colorScheme.outline, 
                widget.election.status, 
                Icons.info_outline);
    }
  }

  Widget _buildTimeRemaining(BuildContext context) {
    final now = DateTime.now();
    final isOpen = widget.election.status.toLowerCase() == 'open';
    final isInProgress = widget.election.status.toLowerCase() == 'in-progress';
    
    if (isOpen && now.isBefore(widget.election.startTime)) {
      final remaining = widget.election.startTime.difference(now);
      return _buildTimeRemainingWidget(
        context, 
        'Starts in ${_formatDuration(remaining)}',
        Icons.schedule_outlined,
        Colors.orange.shade600,
      );
    } else if (isInProgress && now.isBefore(widget.election.endTime)) {
      final remaining = widget.election.endTime.difference(now);
      return _buildTimeRemainingWidget(
        context, 
        'Ends in ${_formatDuration(remaining)}',
        Icons.timer_outlined,
        Colors.green.shade600,
      );
    } else {
      return _buildTimeRemainingWidget(
        context, 
        _formatTimeRange(),
        Icons.event_outlined,
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      );
    }
  }

  Widget _buildTimeRemainingWidget(
    BuildContext context, 
    String text, 
    IconData icon, 
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Row(
      children: [
        Icon(
          Icons.people_outline,
          size: 18,
          color: colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          AppLocalizations.of(context).candidatesCountShort(widget.election.candidates.length),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.8),
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        _buildActionHint(context),
      ],
    );
  }

  Widget _buildActionHint(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Row(
      children: [
        Text(
          'Tap to view',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.arrow_forward_ios,
          size: 12,
          color: colorScheme.primary,
        ),
      ],
    );
  }

  Widget _buildProgressIndicator(BuildContext context) {
    final now = DateTime.now();
    final total = widget.election.endTime.difference(widget.election.startTime);
    final elapsed = now.difference(widget.election.startTime);
    
    double progress = 0.0;
    if (now.isAfter(widget.election.startTime)) {
      progress = elapsed.inMilliseconds / total.inMilliseconds;
      progress = progress.clamp(0.0, 1.0);
    }
    
    final colorScheme = Theme.of(context).colorScheme;
    Color progressColor;
    
    switch (widget.election.status.toLowerCase()) {
      case 'open':
        progressColor = Colors.orange.shade600;
        break;
      case 'in-progress':
        progressColor = Colors.green.shade600;
        break;
      case 'finished':
        progressColor = Colors.blue.shade600;
        progress = 1.0;
        break;
      case 'canceled':
        progressColor = Colors.red.shade600;
        break;
      default:
        progressColor = colorScheme.outline;
    }
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDate(widget.election.startTime),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Text(
              _formatDate(widget.election.endTime),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: colorScheme.outline.withValues(alpha: 0.2),
          valueColor: AlwaysStoppedAnimation<Color>(progressColor),
          minHeight: 4,
          borderRadius: BorderRadius.circular(2),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else {
      return '${duration.inMinutes}m';
    }
  }

  String _formatTimeRange() {
    final startDate = widget.election.startTime;
    final endDate = widget.election.endTime;

    if (startDate.day == endDate.day &&
        startDate.month == endDate.month &&
        startDate.year == endDate.year) {
      return '${_formatTime(startDate)} - ${_formatTime(endDate)}';
    } else {
      return '${_formatDate(startDate)} - ${_formatDate(endDate)}';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _buildSemanticLabel() {
    final status = widget.election.status.toLowerCase();
    final candidatesCount = widget.election.candidates.length;
    
    String timeInfo;
    final now = DateTime.now();
    
    if (status == 'open' && now.isBefore(widget.election.startTime)) {
      final remaining = widget.election.startTime.difference(now);
      timeInfo = 'starts in ${_formatDuration(remaining)}';
    } else if (status == 'in-progress' && now.isBefore(widget.election.endTime)) {
      final remaining = widget.election.endTime.difference(now);
      timeInfo = 'ends in ${_formatDuration(remaining)}';
    } else {
      timeInfo = '${_formatDate(widget.election.startTime)} to ${_formatDate(widget.election.endTime)}';
    }
    
    return 'Election ${widget.election.name}, status $status, $candidatesCount candidates, $timeInfo';
  }
}

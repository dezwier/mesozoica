import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/notification_controller.dart';
import '../../../controllers/xp_award_controller.dart';
import '../../../utils/discovery_haptic.dart';
import '../../../widgets/cards/card_detail_sheet.dart';
import '../../../widgets/cards/site_discovery_celebration.dart';
import '../domain/celebration_event.dart';
import 'celebration_controller.dart';

class CelebrationHost extends StatelessWidget {
  const CelebrationHost({
    super.key,
    required this.child,
    this.eventBuilder,
    this.playHaptic,
  });

  final Widget child;
  final Widget Function(BuildContext context, CelebrationEvent event)?
  eventBuilder;
  final FutureOr<void> Function()? playHaptic;

  @override
  Widget build(BuildContext context) {
    return Consumer<CelebrationController>(
      builder: (context, controller, _) {
        final event = controller.current;
        return PopScope(
          canPop: event == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && event != null) controller.dismissCurrent();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (event != null)
                _VisibleCelebration(
                  key: ValueKey(event.dedupeKey),
                  event: event,
                  eventBuilder: eventBuilder,
                  playHaptic: playHaptic,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _VisibleCelebration extends StatefulWidget {
  const _VisibleCelebration({
    super.key,
    required this.event,
    this.eventBuilder,
    this.playHaptic,
  });

  final CelebrationEvent event;
  final Widget Function(BuildContext context, CelebrationEvent event)?
  eventBuilder;
  final FutureOr<void> Function()? playHaptic;

  @override
  State<_VisibleCelebration> createState() => _VisibleCelebrationState();
}

class _VisibleCelebrationState extends State<_VisibleCelebration> {
  List<XpAward>? _xpAwards;

  @override
  void initState() {
    super.initState();
    CardDetailSheet.dismissMatching(
      CardDetailIdentity.site(widget.event.siteId),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final playHaptic = widget.playHaptic;
      if (playHaptic == null) {
        playDiscoveryHapticFireAndForget();
      } else {
        unawaited(Future<void>.sync(playHaptic));
      }
      final celebrations = context.read<CelebrationController>();
      unawaited(celebrations.markCurrentVisible());
      final notificationId = widget.event.notificationId;
      if (notificationId != null) {
        unawaited(
          context.read<NotificationController>().markRead(notificationId),
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.eventBuilder == null) {
      _xpAwards ??= claimCelebrationXpForKind(context, widget.event.kind);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: CardDetailSheetShell(
        clearTopForXpBadges: false,
        onClose: context.read<CelebrationController>().dismissCurrent,
        child:
            widget.eventBuilder?.call(context, widget.event) ??
            SiteCelebrationCard(event: widget.event, xpAwards: _xpAwards!),
      ),
    );
  }
}

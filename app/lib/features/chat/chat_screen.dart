import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import 'chat_avatar.dart';
import 'chat_profile_screen.dart';
import 'conversations_screen.dart';

/// A single guarded conversation: adab gate before the first message,
/// Wali-visible badge, message stream, contact-info-filtered input,
/// End-with-dua. Every mutation is a callable (rules deny direct writes).
class ChatScreen extends ConsumerStatefulWidget {
  final String convId;
  const ChatScreen({super.key, required this.convId});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  bool _sending = false;

  // Streams created once per screen — recreating them on every rebuild
  // resubscribes Firestore and makes the transcript flicker.
  late final _repo = ref.read(chatRepositoryProvider);
  late final _convStream = _repo.conversationStream(widget.convId);
  late final _msgStream = _repo.messagesStream(widget.convId);
  final _scroll = ScrollController();
  int _lastCount = 0;
  String? _readMarkedFor;
  // Optimistic outbound messages, shown instantly and dropped once the real
  // doc (matched by clientId) arrives on the stream.
  final List<Map<String, String>> _pending = [];
  int _clientSeq = 0;

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    // Optimistic: show it immediately, clear the box, don't block the button.
    final clientId = '${DateTime.now().microsecondsSinceEpoch}_${_clientSeq++}';
    setState(() {
      _pending.add({'clientId': clientId, 'text': text});
      _input.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendMessage(widget.convId, text, clientId: clientId);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() => _pending.removeWhere((p) => p['clientId'] == clientId));
        // The contact-info filter's warning surfaces here.
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: DarkTokens.bg,
            title: Text('Message not sent',
                style: AppType.fraunces(19, color: DarkTokens.ivory)),
            content: Text(e.message ?? 'Please revise your message.',
                style: AppType.inter(13.5,
                    color: DarkTokens.muted(.75), height: 1.6)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Understood',
                      style: AppType.inter(13.5, color: DarkTokens.gold))),
            ],
          ),
        );
      }
    } catch (_) {
      // Network / unknown — drop the optimistic bubble and let them retry.
      if (mounted) {
        setState(() => _pending.removeWhere((p) => p['clientId'] == clientId));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not send. Please try again.',
                style: AppType.inter(13))));
      }
    }
  }

  /// Runs a callable with error feedback — destructive/irreversible actions
  /// must never fail silently. Returns true on success.
  Future<bool> _run(Future<void> Function() action, {String? errorMsg}) async {
    try {
      await action();
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errorMsg ?? 'Something went wrong. Please try again.',
                style: AppType.inter(13))));
      }
      return false;
    }
  }

  static const _reportReasons = {
    'not_serious': 'Not serious about marriage',
    'already_married': 'Already married (undisclosed)',
    'inappropriate': 'Inappropriate content',
    'off_app': 'Asking to move off-app',
    'fake_profile': 'Fake profile',
    'harassment': 'Harassment',
  };

  Future<void> _report(String otherUid) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: DarkTokens.bg,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 16),
          Text('Report — why?',
              style: AppType.fraunces(18, color: DarkTokens.ivory)),
          const SizedBox(height: 8),
          for (final e in _reportReasons.entries)
            ListTile(
              title: Text(e.value,
                  style: AppType.inter(14, color: DarkTokens.ivory)),
              onTap: () => Navigator.pop(ctx, e.key),
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
    if (reason == null) return;
    final ok = await _run(
        () => ref.read(chatRepositoryProvider).reportUser(otherUid, reason,
            convId: widget.convId),
        errorMsg: 'Could not submit the report. Please try again.');
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Reported. Our team reviews within 24 hours; this conversation '
              'is frozen meanwhile.',
              style: AppType.inter(13))));
    }
  }

  Future<void> _block(String otherUid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DarkTokens.bg,
        title: Text('Block this person?',
            style: AppType.fraunces(19, color: DarkTokens.ivory)),
        content: Text(
            'You will become permanently invisible to each other and this '
            'conversation closes. This cannot be undone.',
            style: AppType.inter(13.5, color: DarkTokens.muted(.75), height: 1.6)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: AppType.inter(13.5, color: DarkTokens.gold))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Block',
                  style: AppType.inter(13.5, color: DarkTokens.muted()))),
        ],
      ),
    );
    if (ok == true) {
      final done = await _run(
          () => ref.read(chatRepositoryProvider).blockUser(otherUid),
          errorMsg: 'Could not block. Please try again.');
      if (done && mounted) context.go('/conversations');
    }
  }

  Future<void> _endWithDua() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DarkTokens.bg,
        title: Text('End with dua?',
            style: AppType.fraunces(19, color: DarkTokens.ivory)),
        content: Text(
            'A respectful closing message is sent and the conversation '
            'closes. This cannot be reopened.',
            style: AppType.inter(13.5, color: DarkTokens.muted(.75), height: 1.6)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Keep talking',
                  style: AppType.inter(13.5, color: DarkTokens.gold))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('End with dua',
                  style: AppType.inter(13.5, color: DarkTokens.muted()))),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => ref.read(chatRepositoryProvider).endWithDua(widget.convId),
          errorMsg: 'Could not end the conversation. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    // Auth dropped (sign-out/token revoke) — the router redirect is about to
    // take over; don't crash on a stale build.
    if (user == null) {
      return const IkhlasScaffold(child: SizedBox.shrink());
    }
    final me = user.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _convStream,
      builder: (context, convSnap) {
        final conv = convSnap.data?.data();
        if (conv == null) {
          return const IkhlasScaffold(
              child: Center(child: CircularProgressIndicator()));
        }
        final stage = conv['stage'] as String? ?? 'intro';
        final closed = ConversationsScreen.isClosed(stage);
        final frozen = conv['frozen'] == true;
        final adab = (conv['adabAcknowledged'] as Map?) ?? {};
        final needsAdab = adab[me] != true && !closed;
        final waliVisible = conv['waliObserving'] == true;
        final other = (conv['participants'] as List)
            .firstWhere((p) => p != me, orElse: () => '') as String;
        final fs = (conv['familyStage'] as Map?) ?? {};
        final familyExchange = conv['familyExchange'] as Map?;
        final profiles = (conv['profiles'] as Map?) ?? const {};
        final otherProfile =
            (profiles[other] as Map?)?.cast<String, dynamic>();
        final myProfile = (profiles[me] as Map?)?.cast<String, dynamic>();
        final photoReveal = (conv['photoReveal'] as Map?) ?? const {};
        final photoRevealRequests =
            (conv['photoRevealRequests'] as Map?) ?? const {};
        final revealBar = _photoRevealBar(
          me: me,
          other: other,
          otherProfile: otherProfile,
          myProfile: myProfile,
          photoReveal: photoReveal,
          photoRevealRequests: photoRevealRequests,
        );

        return IkhlasScaffold(
          safeArea: true,
          child: Column(children: [
            _header(context, stage, closed, other, otherProfile,
                photoRevealed: photoReveal[other] == true),
            if (waliVisible) _waliBadge(),
            if (needsAdab)
              Expanded(child: _AdabGate(convId: widget.convId))
            else ...[
              if (revealBar != null && !closed) revealBar,
              Expanded(child: _messages(me, other, conv)),
              if (familyExchange != null)
                _familyPanel(familyExchange, me, other)
              else if (!closed && !frozen)
                _familyStageBar(fs, me),
              if (frozen)
                _frozenNotice()
              else if (!closed)
                _composer()
              else
                _closedNotice(stage),
            ],
          ]),
        );
      },
    );
  }

  static const _stageTitle = {
    'intro': 'Introduction stage',
    'deepening': 'Deepening stage',
    'family': 'Family stage',
    'closed_dua': 'Ended with dua',
    'closed_timeout': 'Rested (14-day)',
    'closed_blocked': 'Blocked',
  };

  void _openProfile(String other, Map<String, dynamic>? profile,
      {bool photoRevealed = false}) {
    if (profile == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatProfileScreen(
          ownerUid: other, profile: profile, photoRevealed: photoRevealed),
    ));
  }

  Widget _header(BuildContext context, String stage, bool closed, String other,
          Map<String, dynamic>? otherProfile,
          {bool photoRevealed = false}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
        child: Row(children: [
          IconButton(
            onPressed: () => context.go('/conversations'),
            icon: Icon(Icons.arrow_back, size: 22, color: DarkTokens.muted(.7)),
          ),
          if (otherProfile != null) ...[
            ChatAvatar(
                ownerUid: other,
                profile: otherProfile,
                photoRevealed: photoRevealed,
                size: 38),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: otherProfile == null
                  ? null
                  : () => _openProfile(other, otherProfile,
                      photoRevealed: photoRevealed),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                          otherProfile?['displayName'] as String? ??
                              'Your match',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.inter(15,
                              weight: FontWeight.w600,
                              color: DarkTokens.ivory)),
                    ),
                    if (otherProfile != null) ...[
                      const SizedBox(width: 5),
                      Icon(Icons.chevron_right,
                          size: 16, color: DarkTokens.muted(.6)),
                    ],
                  ]),
                  Text(_stageTitle[stage] ?? stage,
                      style: AppType.inter(11.5, color: DarkTokens.muted(.7))),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            color: DarkTokens.bg,
            icon: Icon(Icons.more_vert, size: 20, color: DarkTokens.muted(.7)),
            onSelected: (v) {
              if (v == 'dua') _endWithDua();
              if (v == 'report') _report(other);
              if (v == 'block') _block(other);
            },
            itemBuilder: (_) => [
              if (!closed)
                PopupMenuItem(
                    value: 'dua',
                    child: Text('End with dua',
                        style: AppType.inter(13.5, color: DarkTokens.gold))),
              PopupMenuItem(
                  value: 'report',
                  child: Text('Report',
                      style: AppType.inter(13.5, color: DarkTokens.ivory))),
              PopupMenuItem(
                  value: 'block',
                  child: Text('Block',
                      style: AppType.inter(13.5, color: DarkTokens.ivory))),
            ],
          ),
        ]),
      );

  /// "Involve families" bar (PRD §4.4 Stage 3). Either party requests;
  /// the other confirms; then guardian contacts are exchanged.
  Widget _familyStageBar(Map fs, String me) {
    final requestedBy = fs['requestedBy'] as String?;
    if (requestedBy == null) {
      return _bar(
        'Ready to involve families?',
        'Involve families',
        () => _run(
            () => ref.read(chatRepositoryProvider)
                .requestFamilyStage(widget.convId),
            errorMsg: 'Could not send the request. Please try again.'),
      );
    }
    if (requestedBy == me) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Text('You asked to involve families — waiting for them to agree.',
            textAlign: TextAlign.center,
            style: AppType.inter(12.5, color: DarkTokens.muted())),
      );
    }
    return _bar(
      'They asked to involve families.',
      'Agree & exchange guardians',
      () => _run(
          () => ref.read(chatRepositoryProvider)
              .confirmFamilyStage(widget.convId),
          errorMsg: 'Could not confirm. Please try again.'),
    );
  }

  Widget _bar(String label, String cta, VoidCallback onTap) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: DarkTokens.hairline(.3)))),
        child: Column(children: [
          Text(label,
              style: AppType.inter(12.5, color: DarkTokens.muted())),
          const SizedBox(height: 8),
          SizedBox(height: 44, child: PrimaryCta(label: cta, onPressed: onTap)),
        ]),
      );

  Widget _familyPanel(Map exchange, String me, String other) {
    final theirs = exchange[other] as Map?;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DarkTokens.gold.withOpacity(.06),
        border: Border(top: BorderSide(color: DarkTokens.hairline(.4))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('FAMILY STAGE · GUARDIAN CONTACT',
            style: AppType.eyebrow(DarkTokens.gold)),
        const SizedBox(height: 8),
        if (theirs == null)
          Text('Their guardian details will appear once they are provided.',
              style: AppType.inter(13, color: DarkTokens.muted()))
        else ...[
          Text('${theirs['name'] ?? 'Guardian'} · ${theirs['relationship'] ?? ''}',
              style: AppType.inter(15, color: DarkTokens.ivory)),
          const SizedBox(height: 2),
          Text('${theirs['phone'] ?? ''}',
              style: AppType.inter(14, color: DarkTokens.gold)),
        ],
        const SizedBox(height: 6),
        Text('Take things forward with your families, insha’Allah.',
            style: AppType.inter(12, color: DarkTokens.muted())),
      ]),
    );
  }

  Widget _frozenNotice() => Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'This conversation is frozen pending a moderation review.',
          textAlign: TextAlign.center,
          style: AppType.inter(12.5, color: DarkTokens.muted()),
        ),
      );

  Widget _waliBadge() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        color: DarkTokens.gold.withOpacity(.08),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const DiamondBullet(size: 6),
          const SizedBox(width: 8),
          Text('This conversation is visible to her Wali',
              style: AppType.inter(12, color: DarkTokens.gold)),
        ]),
      );

  /// Shows a banner when photo reveal is pending — either they've asked to
  /// see your (request_only) photos and you can grant, or their photos are
  /// request_only and you can ask. Returns null when nothing is pending.
  Widget? _photoRevealBar({
    required String me,
    required String other,
    required Map<String, dynamic>? otherProfile,
    required Map<String, dynamic>? myProfile,
    required Map photoReveal,
    required Map photoRevealRequests,
  }) {
    // Only 'on_mutual_hidden' photos involve a request; 'public' and
    // 'on_mutual_blur' auto-reveal symmetrically on the match (no button).
    // 1. They asked to see MY photos and I haven't revealed yet → grant.
    final iAmHidden = myProfile?['photoVisibility'] == 'on_mutual_hidden';
    if (iAmHidden &&
        myProfile?['hasPhotos'] == true &&
        photoRevealRequests[other] == true &&
        photoReveal[me] != true) {
      return _revealBanner(
        'They have asked to see your photos.',
        cta: 'Reveal my photos',
        onTap: () => _run(
            () => ref.read(chatRepositoryProvider).grantPhotoReveal(widget.convId),
            errorMsg: 'Could not reveal. Please try again.'),
      );
    }
    // 2. Their photos are hidden and not yet revealed → ask / waiting.
    final theyHidden = otherProfile?['photoVisibility'] == 'on_mutual_hidden';
    if (theyHidden &&
        otherProfile?['hasPhotos'] == true &&
        photoReveal[other] != true) {
      if (photoRevealRequests[me] == true) {
        return _revealBanner(
          'Photo request sent — you will see them if they agree.',
          cta: null,
        );
      }
      return _revealBanner(
        'Their photos are private.',
        cta: 'Request to see',
        onTap: () async {
          final ok = await _run(
              () => ref.read(chatRepositoryProvider)
                  .requestPhotoReveal(widget.convId),
              errorMsg: 'Could not send the request. Please try again.');
          if (ok && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Photo request sent.',
                    style: AppType.inter(13))));
          }
        },
      );
    }
    return null;
  }

  Widget _revealBanner(String label, {String? cta, VoidCallback? onTap}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
        decoration: BoxDecoration(
          color: DarkTokens.gold.withOpacity(.06),
          border: Border(bottom: BorderSide(color: DarkTokens.hairline(.3))),
        ),
        child: Row(children: [
          Icon(Icons.photo_camera_back_outlined,
              size: 17, color: DarkTokens.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: AppType.inter(12.5, color: DarkTokens.muted(.85))),
          ),
          if (cta != null)
            TextButton(
              onPressed: onTap,
              child: Text(cta,
                  style: AppType.inter(13,
                      weight: FontWeight.w600, color: DarkTokens.gold)),
            ),
        ]),
      );

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${d.day} ${_months[d.month - 1]}'
        '${d.year == now.year ? '' : ' ${d.year}'}';
  }

  String _timeLabel(DateTime d) {
    final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  Widget _dateDivider(DateTime day) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: DarkTokens.ivory.withOpacity(.04),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_dayLabel(day),
                style: AppType.inter(11, color: DarkTokens.muted(.7))),
          ),
        ),
      );

  Widget _messages(String me, String other, Map<String, dynamic> conv) {
    final readUpTo = (conv['readUpTo'] as Map?) ?? const {};
    final deliveredUpTo = (conv['deliveredUpTo'] as Map?) ?? const {};
    final otherRead = readUpTo[other] as Timestamp?;
    final otherDelivered = deliveredUpTo[other] as Timestamp?;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _msgStream,
      builder: (context, snap) {
        final msgs = snap.data?.docs ?? [];
        // Keep the latest message in view as the thread grows.
        if (msgs.length != _lastCount) {
          _lastCount = msgs.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              _scroll.animateTo(_scroll.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut);
            }
          });
        }
        // Mark read once when the newest message is inbound (they'll see the
        // blue ticks on their side). Throttled by the last message id.
        if (msgs.isNotEmpty) {
          final last = msgs.last;
          if (last.data()['from'] != me && _readMarkedFor != last.id) {
            _readMarkedFor = last.id;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(chatRepositoryProvider).markRead(widget.convId);
            });
          }
        }
        // Confirmed clientIds → drop the matching optimistic bubbles.
        final confirmed = <String>{};
        for (final doc in msgs) {
          final cid = doc.data()['clientId'];
          if (cid is String) confirmed.add(cid);
        }
        if (_pending.any((p) => confirmed.contains(p['clientId']))) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _pending
                  .removeWhere((p) => confirmed.contains(p['clientId'])));
            }
          });
        }

        // Flatten into a display list with date dividers between days.
        final items = <Widget>[];
        DateTime? lastDay;
        for (final doc in msgs) {
          final m = doc.data();
          final at = m['at'];
          final dt = at is Timestamp ? at.toDate() : null;
          if (dt != null) {
            final day = DateTime(dt.year, dt.month, dt.day);
            if (lastDay == null || day != lastDay) {
              items.add(_dateDivider(day));
              lastDay = day;
            }
          }
          items.add(_bubble(m, me, dt, otherRead, otherDelivered));
        }
        // Optimistic messages not yet confirmed by the server, at the bottom.
        for (final p in _pending) {
          if (confirmed.contains(p['clientId'])) continue;
          items.add(_pendingBubble(p['text'] ?? ''));
        }
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          itemCount: items.length,
          itemBuilder: (_, i) => items[i],
        );
      },
    );
  }

  Widget _bubble(Map<String, dynamic> m, String me, DateTime? dt,
      Timestamp? otherRead, Timestamp? otherDelivered) {
    if (m['system'] == true) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(m['text'] ?? '',
              textAlign: TextAlign.center,
              style: AppType.fraunces(14,
                  color: DarkTokens.muted(.75), style: FontStyle.italic)),
        ),
      );
    }
    final mine = m['from'] == me;
    final at = m['at'];
    final receipt = mine ? _receipt(at, otherRead, otherDelivered) : null;
    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * .72),
            decoration: BoxDecoration(
              color: mine
                  ? DarkTokens.gold.withOpacity(.14)
                  : DarkTokens.ivory.withOpacity(.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DarkTokens.hairline(.3)),
            ),
            child: Text(m['text'] ?? '',
                style: AppType.inter(14, color: DarkTokens.ivory)),
          ),
        ),
        if (dt != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 2, left: 2, right: 2),
            child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment:
                    mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Text(_timeLabel(dt),
                      style: AppType.inter(10, color: DarkTokens.muted(.55))),
                  if (receipt != null) ...[
                    const SizedBox(width: 4),
                    receipt,
                  ],
                ]),
          ),
      ],
    );
  }

  /// WhatsApp-style receipt for one of MY messages: single tick = sent, double
  /// tick = delivered, blue double = read. Compares the message time against
  /// the other party's read/delivered high-water marks.
  Widget _receipt(dynamic at, Timestamp? otherRead, Timestamp? otherDelivered) {
    // No server timestamp yet (optimistic/pending write) → single tick.
    if (at is! Timestamp) {
      return Icon(Icons.check, size: 13, color: DarkTokens.muted(.5));
    }
    if (otherRead != null && otherRead.compareTo(at) >= 0) {
      return const Icon(Icons.done_all, size: 13, color: Color(0xFF2E7D32));
    }
    if (otherDelivered != null && otherDelivered.compareTo(at) >= 0) {
      return Icon(Icons.done_all, size: 13, color: DarkTokens.muted(.5));
    }
    return Icon(Icons.check, size: 13, color: DarkTokens.muted(.5));
  }

  /// An optimistic (not-yet-confirmed) outbound message — instant echo with a
  /// clock instead of a tick until the server write lands on the stream.
  Widget _pendingBubble(String text) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * .72),
              decoration: BoxDecoration(
                color: DarkTokens.gold.withOpacity(.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DarkTokens.hairline(.3)),
              ),
              child: Text(text,
                  style: AppType.inter(14, color: DarkTokens.ivory)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 2, right: 2),
            child: Icon(Icons.access_time, size: 12, color: DarkTokens.muted(.5)),
          ),
        ],
      );

  Widget _composer() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              style: AppType.inter(15, color: DarkTokens.ivory),
              cursorColor: DarkTokens.gold,
              decoration: InputDecoration(
                hintText: 'Write with adab…',
                hintStyle: AppType.inter(14, color: DarkTokens.muted(.4)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    borderSide: BorderSide(color: DarkTokens.hairline(.4))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    borderSide:
                        BorderSide(color: DarkTokens.gold.withOpacity(.7))),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.send, color: DarkTokens.gold),
          ),
        ]),
      );

  Widget _closedNotice(String stage) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          stage == 'closed_dua'
              ? 'This conversation was ended with dua.'
              : 'This conversation rested after 14 days and was closed.',
          textAlign: TextAlign.center,
          style: AppType.inter(12.5, color: DarkTokens.muted()),
        ),
      );
}

/// One-time adab (etiquette) screen — the bismillah moment before the
/// first message (PRD §4.4). Acknowledgement is per-participant.
class _AdabGate extends ConsumerStatefulWidget {
  final String convId;
  const _AdabGate({required this.convId});
  @override
  ConsumerState<_AdabGate> createState() => _AdabGateState();
}

class _AdabGateState extends ConsumerState<_AdabGate> {
  bool _busy = false;

  static const _adab = [
    'Speak with the intention of nikah — this is not casual conversation.',
    'Maintain haya (modesty) in every message, as if a guardian is present.',
    'No contact details or moving off Ikhlaas before the Family Stage.',
    'If it is not a match, end with dua — never ghosting.',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.screenMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Text('بِسْمِ اللَّهِ',
                style: AppType.amiri(22, color: DarkTokens.gold)),
          ),
          const SizedBox(height: 24),
          Text('Before you begin',
              style: AppType.fraunces(28, color: DarkTokens.ivory)),
          const SizedBox(height: 8),
          Text('A few words of adab for this conversation.',
              style: AppType.inter(14, color: DarkTokens.muted(.62))),
          const SizedBox(height: 28),
          for (final a in _adab) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: DiamondBullet(size: 6)),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(a,
                      style: AppType.inter(14.5,
                          color: DarkTokens.ivory, height: 1.55))),
            ]),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 20),
          PrimaryCta(
            label: 'I understand — begin',
            loading: _busy,
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await ref
                          .read(chatRepositoryProvider)
                          .acknowledgeAdab(widget.convId);
                      // On success the conversation stream replaces this gate.
                    } catch (_) {
                      if (mounted) {
                        setState(() => _busy = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Could not continue. Please try again.',
                                style: AppType.inter(13))));
                      }
                    }
                  },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

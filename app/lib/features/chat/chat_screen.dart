import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
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

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(chatRepositoryProvider).sendMessage(widget.convId, text);
      _input.clear();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
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
    } finally {
      if (mounted) setState(() => _sending = false);
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
    await ref.read(chatRepositoryProvider).reportUser(otherUid, reason,
        convId: widget.convId);
    if (mounted) {
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
      await ref.read(chatRepositoryProvider).blockUser(otherUid);
      if (mounted) context.go('/conversations');
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
      await ref.read(chatRepositoryProvider).endWithDua(widget.convId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!.uid;

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

        return IkhlasScaffold(
          safeArea: true,
          child: Column(children: [
            _header(context, stage, closed, other),
            if (waliVisible) _waliBadge(),
            if (needsAdab)
              Expanded(child: _AdabGate(convId: widget.convId))
            else ...[
              Expanded(child: _messages(me)),
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

  Widget _header(BuildContext context, String stage, bool closed, String other) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
        child: Row(children: [
          IconButton(
            onPressed: () => context.go('/conversations'),
            icon: Icon(Icons.arrow_back, size: 22, color: DarkTokens.muted(.7)),
          ),
          Expanded(
            child: Text(_stageTitle[stage] ?? stage,
                style: AppType.inter(14, weight: FontWeight.w500,
                    color: DarkTokens.ivory)),
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
        () => ref.read(chatRepositoryProvider).requestFamilyStage(widget.convId),
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
      () => ref.read(chatRepositoryProvider).confirmFamilyStage(widget.convId),
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

  Widget _messages(String me) {
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
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final m = msgs[i].data();
            if (m['system'] == true) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text(m['text'] ?? '',
                      textAlign: TextAlign.center,
                      style: AppType.fraunces(14,
                          color: DarkTokens.muted(.75),
                          style: FontStyle.italic)),
                ),
              );
            }
            final mine = m['from'] == me;
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            );
          },
        );
      },
    );
  }

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
                    await ref
                        .read(chatRepositoryProvider)
                        .acknowledgeAdab(widget.convId);
                  },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

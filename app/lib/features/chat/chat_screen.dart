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
    final repo = ref.read(chatRepositoryProvider);
    final me = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: repo.conversationStream(widget.convId),
      builder: (context, convSnap) {
        final conv = convSnap.data?.data();
        if (conv == null) {
          return const IkhlasScaffold(
              child: Center(child: CircularProgressIndicator()));
        }
        final stage = conv['stage'] as String? ?? 'intro';
        final closed = ConversationsScreen.isClosed(stage);
        final adab = (conv['adabAcknowledged'] as Map?) ?? {};
        final needsAdab = adab[me] != true && !closed;
        final waliVisible = conv['waliObserving'] == true;

        return IkhlasScaffold(
          safeArea: true,
          child: Column(children: [
            _header(context, stage, closed),
            if (waliVisible) _waliBadge(),
            if (needsAdab)
              Expanded(child: _AdabGate(convId: widget.convId))
            else ...[
              Expanded(child: _messages(me)),
              if (!closed) _composer() else _closedNotice(stage),
            ],
          ]),
        );
      },
    );
  }

  Widget _header(BuildContext context, String stage, bool closed) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
        child: Row(children: [
          IconButton(
            onPressed: () => context.go('/conversations'),
            icon: Icon(Icons.arrow_back, size: 22, color: DarkTokens.muted(.7)),
          ),
          Expanded(
            child: Text('Introduction stage',
                style: AppType.inter(14, weight: FontWeight.w500,
                    color: DarkTokens.ivory)),
          ),
          if (!closed)
            TextButton(
              onPressed: _endWithDua,
              child: Text('End with dua',
                  style: AppType.inter(12.5, color: DarkTokens.gold)),
            ),
        ]),
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
      stream: ref.read(chatRepositoryProvider).messagesStream(widget.convId),
      builder: (context, snap) {
        final msgs = snap.data?.docs ?? [];
        return ListView.builder(
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
    'No contact details or moving off Ikhlas before the Family Stage.',
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

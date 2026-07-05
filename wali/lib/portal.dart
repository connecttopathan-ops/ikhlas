import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// What the Wali sees: the ward's conversations (stage always; transcripts
/// only when she granted "observe"), Family Stage requests, and a gentle
/// "Request pause" action. He never sees anyone else's matches.
class WaliPortal extends StatelessWidget {
  final String ward;
  const WaliPortal({super.key, required this.ward});

  static const _stageLabel = {
    'intro': 'Getting to know each other',
    'deepening': 'Deepening',
    'family': 'Families involved',
    'closed_dua': 'Ended respectfully',
    'closed_timeout': 'Closed (inactivity)',
    'closed_blocked': 'Closed',
    'success': 'Proceeding to nikah',
  };

  @override
  Widget build(BuildContext context) {
    final convs = FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: ward);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              const SizedBox(height: 12),
              Text('Ikhlaas', style: T.fraunces(30, color: T.gold)),
              const SizedBox(height: 4),
              Text('Your ward’s conversations',
                  style: T.inter(15, color: T.muted)),
              const SizedBox(height: 8),
              Text(
                  'You are here as a trusted guardian. What you see reflects '
                  'the visibility she has chosen.',
                  style: T.inter(13, color: T.muted, height: 1.6)),
              const SizedBox(height: 24),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: convs.snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data!.docs;
                  if (docs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text('No conversations yet.',
                          textAlign: TextAlign.center,
                          style: T.inter(14, color: T.muted)),
                    );
                  }
                  return Column(
                    children: [for (final d in docs) _ConvCard(doc: d)],
                  );
                },
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () async {
                  await FirebaseFunctions.instanceFor(region: 'asia-south1')
                      .httpsCallable('waliRequestPause')
                      .call();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Your concern has been shared with her.',
                            style: T.inter(13))));
                  }
                },
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: T.hairline),
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: Text('Request a pause / raise a concern',
                    style: T.inter(14, color: T.gold)),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: Text('Sign out',
                      style: T.inter(13, color: T.muted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConvCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _ConvCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final stage = d['stage'] as String? ?? 'intro';
    final observing = d['waliObserving'] == true;
    final family = d['familyStage']?['requestedBy'] != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: T.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(WaliPortal._stageLabel[stage] ?? stage,
            style: T.fraunces(18, color: T.ivory)),
        if (family) ...[
          const SizedBox(height: 6),
          Text('A request to involve families has been made.',
              style: T.inter(13, color: T.gold)),
        ],
        const SizedBox(height: 12),
        if (observing)
          _Transcript(convId: doc.id)
        else
          Text(
              'She has chosen to share the stage of this conversation, but '
              'not its messages.',
              style: T.inter(12.5, color: T.muted, height: 1.5)),
      ]),
    );
  }
}

class _Transcript extends StatelessWidget {
  final String convId;
  const _Transcript({required this.convId});

  @override
  Widget build(BuildContext context) {
    final msgs = FirebaseFirestore.instance
        .collection('conversations')
        .doc(convId)
        .collection('messages')
        .orderBy('at');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: msgs.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Text('No messages yet.',
              style: T.inter(12.5, color: T.muted));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final m in docs)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  m.data()['system'] == true
                      ? '• ${m.data()['text']}'
                      : m.data()['text'] ?? '',
                  style: T.inter(13,
                      color: m.data()['system'] == true ? T.muted : T.ivory,
                      height: 1.5),
                ),
              ),
          ],
        );
      },
    );
  }
}

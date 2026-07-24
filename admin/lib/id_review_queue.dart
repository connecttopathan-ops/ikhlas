import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Government-ID verification review (PRD Step 4A). Lists documents awaiting
/// manual review. OCR name-match + face-presence are decision SUPPORT only —
/// the moderator visually compares the ID photo against the selfie and makes
/// the call. Images are fetched on demand through a moderator-only callable
/// (the quarantine bucket is never exposed to the client).
class IdReviewQueue extends StatelessWidget {
  const IdReviewQueue({super.key});

  @override
  Widget build(BuildContext context) {
    // Equality-only query (no composite index needed); sorted client-side.
    final q = FirebaseFirestore.instance
        .collection('idReview')
        .where('status', isEqualTo: 'submitted');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
              child: Text('Could not load ID queue.\n${snap.error}',
                  style: T.inter(13, color: T.muted)));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = [...snap.data!.docs]..sort((a, b) {
            final ta = a.data()['submittedAt'] as Timestamp?;
            final tb = b.data()['submittedAt'] as Timestamp?;
            return (ta?.millisecondsSinceEpoch ?? 0)
                .compareTo(tb?.millisecondsSinceEpoch ?? 0);
          });
        if (docs.isEmpty) {
          return Center(
              child: Text('No IDs awaiting review.',
                  style: T.inter(14, color: T.muted)));
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [for (final d in docs) _IdCard(uid: d.id, data: d.data())],
        );
      },
    );
  }
}

class _IdCard extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> data;
  const _IdCard({required this.uid, required this.data});
  @override
  State<_IdCard> createState() => _IdCardState();
}

class _IdCardState extends State<_IdCard> {
  final _fns = FirebaseFunctions.instanceFor(region: 'asia-south1');
  String? _idUrl, _selfieUrl;
  bool _loadingImg = false, _busy = false;

  static const _imgBase =
      'https://asia-south1-ikhlas-caecf.cloudfunctions.net/idDocImageRaw';

  Future<void> _loadImages() async {
    setState(() => _loadingImg = true);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw 'Not signed in';
      setState(() {
        _idUrl = '$_imgBase?uid=${widget.uid}&which=id&token=$token';
        _selfieUrl = '$_imgBase?uid=${widget.uid}&which=selfie&token=$token';
      });
    } catch (e) {
      _snack('Could not load images: $e');
    } finally {
      if (mounted) setState(() => _loadingImg = false);
    }
  }

  Future<void> _review(String decision) async {
    String? reason;
    if (decision == 'reject') {
      reason = await _askReason();
      if (reason == null) return; // cancelled
    }
    setState(() => _busy = true);
    try {
      await _fns.httpsCallable('reviewIdDoc').call({
        'uid': widget.uid,
        'decision': decision,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });
      _snack(decision == 'approve' ? 'Approved — user is now in the pool.' : 'Rejected.');
    } catch (e) {
      _snack('Failed: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.bg,
        title: Text('Reject — reason (optional)', style: T.inter(15, color: T.ivory)),
        content: TextField(
          controller: c,
          style: T.inter(14, color: T.ivory),
          decoration: const InputDecoration(hintText: 'Shown to the applicant'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text('Reject', style: T.inter(14, color: T.gold))),
        ],
      ),
    );
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m, style: T.inter(13))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final name = d['applicationName'] ?? '—';
    final type = d['type'] ?? '—';
    final nameScore = d['nameMatchScore'];
    final last4 = d['last4'] ?? '—';
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      constraints: const BoxConstraints(maxWidth: 760),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: T.hairline),
        color: T.panel,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('$name', style: T.fraunces(20, color: T.ivory)),
          ),
          _chip(type.toString().toUpperCase()),
        ]),
        const SizedBox(height: 4),
        Text('uid ${widget.uid}', style: T.inter(11.5, color: T.muted)),
        const SizedBox(height: 14),
        Wrap(spacing: 20, runSpacing: 8, children: [
          _stat('Name match', nameScore == null ? '—' : '${((nameScore as num) * 100).round()}%'),
          _stat('OCR name', (d['ocrName'] ?? '—').toString()),
          _stat('ID last4', last4.toString()),
          _stat('Face match', 'Manual — compare below'),
          _stat('Face on ID', _yn(d['idFacePresent'])),
          _stat('Face on selfie', _yn(d['selfieFacePresent'])),
          _stat('Liveness', _yn(d['livenessPassed'])),
        ]),
        const SizedBox(height: 16),
        if (_idUrl == null && !_loadingImg)
          OutlinedButton.icon(
            onPressed: _loadImages,
            icon: const Icon(Icons.image_outlined, size: 18),
            label: Text('Reveal ID + selfie', style: T.inter(13)),
          ),
        if (_loadingImg) const Center(child: Padding(
          padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
        if (_idUrl != null) _images(),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : () => _review('approve'),
              style: FilledButton.styleFrom(
                  backgroundColor: T.gold, foregroundColor: T.ctaText),
              child: Text(_busy ? '…' : 'Approve → pool entry',
                  style: T.inter(14, weight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => _review('reject'),
              child: Text('Reject → needs info', style: T.inter(14, color: T.ivory)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _images() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _labelled('ID document', _idUrl)),
        const SizedBox(width: 14),
        Expanded(child: _labelled('Selfie (on file)', _selfieUrl)),
      ]);

  Widget _labelled(String label, String? url) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: T.inter(11.5, color: T.muted)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: url == null
                ? Container(
                    height: 220,
                    alignment: Alignment.center,
                    color: Colors.black26,
                    child: Text('none', style: T.inter(12, color: T.muted)))
                : Image.network(url,
                    height: 220, width: double.infinity, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                        height: 220,
                        alignment: Alignment.center,
                        color: Colors.black26,
                        child: Text('could not load',
                            style: T.inter(12, color: T.muted)))),
          ),
        ],
      );

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: T.gold),
        ),
        child: Text(t, style: T.inter(11, weight: FontWeight.w600, color: T.gold)),
      );

  Widget _stat(String k, String v) => SizedBox(
        width: 150,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: T.inter(11, color: T.muted)),
          const SizedBox(height: 2),
          Text(v, style: T.inter(13.5, color: T.ivory)),
        ]),
      );

  String _yn(dynamic v) => v == true ? 'Yes' : v == false ? 'No' : '—';
}

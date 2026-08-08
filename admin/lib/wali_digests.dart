import 'dart:convert';
import 'dart:html' as html; // admin is a web-only app

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tokens.dart';

/// Wali digest outbox (PRD §4.5). The weekly `sendWaliDigests` function drops
/// a pending digest here for each observing guardian. A moderator taps
/// "Open WhatsApp" — their own WhatsApp opens with the notice pre-typed to the
/// guardian's number — sends it, then marks it sent. This is the ToS-clean,
/// human-in-the-loop path used until the Cloud API / wali portal is live.
class WaliDigestsQueue extends StatelessWidget {
  const WaliDigestsQueue({super.key});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('waliDigests')
        .where('status', isEqualTo: 'pending');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = [...snap.data!.docs]..sort((a, b) {
            final ta =
                (a.data()['at'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final tb =
                (b.data()['at'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return ta.compareTo(tb); // oldest first
          });
        if (docs.isEmpty) {
          return Center(
              child: Text('No digests waiting to be sent.',
                  style: T.inter(15, color: T.muted)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: docs.length,
          itemBuilder: (_, i) => _DigestCard(doc: docs[i]),
        );
      },
    );
  }
}

class _DigestCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _DigestCard({required this.doc});
  @override
  State<_DigestCard> createState() => _DigestCardState();
}

class _DigestCardState extends State<_DigestCard> {
  bool _busy = false;

  Future<void> _openWhatsApp() async {
    final link = widget.doc.data()['waLink'] as String?;
    if (link == null) {
      _snack('No phone number on file for this guardian.');
      return;
    }
    final ok = await launchUrl(Uri.parse(link),
        mode: LaunchMode.externalApplication);
    if (!ok) _snack('Could not open WhatsApp.');
  }

  /// Downloads the digest as a .txt file so it can be attached in WhatsApp.
  void _download() {
    final d = widget.doc.data();
    final text = (d['waMessage'] ?? d['transcript'] ?? '').toString();
    if (text.isEmpty) {
      _snack('Nothing to download.');
      return;
    }
    final name = (d['waliName'] ?? 'guardian')
        .toString()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
    final bytes = utf8.encode(text);
    final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes], 'text/plain'));
    html.AnchorElement(href: url)
      ..setAttribute('download', 'wali-digest-$name.txt')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _markSent() async {
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('markWaliDigestSent')
          .call({'id': widget.doc.id});
      // The stream drops this card once status flips off 'pending'.
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('Failed: $e');
      }
    }
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data();
    final count = d['messageCount'] ?? 0;
    // The exact text that gets sent — full transcript included.
    final message =
        (d['waMessage'] ?? d['notice'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(22),
      constraints: const BoxConstraints(maxWidth: 760),
      decoration: BoxDecoration(
        color: T.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Wali of ${d['waliName'] ?? 'guardian'}',
            style: T.fraunces(18, color: T.ivory)),
        const SizedBox(height: 4),
        Text('$count new message${count == 1 ? '' : 's'} to notify',
            style: T.inter(12.5, color: T.muted)),
        Text('Send to guardian: ${d['waliPhone']?.toString() ?? 'no phone on file'}',
            style: T.inter(12.5, color: T.gold)),
        if ((d['sendFrom'] ?? '').toString().isNotEmpty)
          Text('From WhatsApp: ${d['sendFrom']}',
              style: T.inter(12.5, color: T.muted)),
        const SizedBox(height: 14),
        // The exact message that will be sent — full transcript included.
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 280),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: T.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: T.hairline),
          ),
          child: SingleChildScrollView(
            child: SelectableText(message,
                style: T.inter(13.5, color: T.ivory, height: 1.5)),
          ),
        ),
        const SizedBox(height: 16),
        if (_busy)
          const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
        else
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.icon(
              onPressed: widget.doc.data()['waLink'] == null
                  ? null
                  : _openWhatsApp,
              style: FilledButton.styleFrom(
                  backgroundColor: T.approve, foregroundColor: T.ivory),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: Text('Open WhatsApp',
                  style: T.inter(13, weight: FontWeight.w600)),
            ),
            OutlinedButton.icon(
              onPressed: _download,
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: T.muted.withOpacity(.5))),
              icon: Icon(Icons.download, size: 16, color: T.ivory),
              label: Text('Download', style: T.inter(13, color: T.ivory)),
            ),
            OutlinedButton(
              onPressed: _markSent,
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: T.gold.withOpacity(.6))),
              child: Text('Mark sent', style: T.inter(13, color: T.gold)),
            ),
          ]),
      ]),
    );
  }
}

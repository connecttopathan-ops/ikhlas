import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Family Stage access gate (config/featureFlags.familyStage). The app's most
/// safety-sensitive surface stays locked until CA/legal sign-off; before that
/// it runs only for the tester allowlist. This tab is the operator control —
/// no more editing raw Firestore. All writes go through a moderator-only
/// callable (config/* is not client-writable).
class FamilyGateScreen extends StatefulWidget {
  const FamilyGateScreen({super.key});
  @override
  State<FamilyGateScreen> createState() => _FamilyGateScreenState();
}

class _FamilyGateScreenState extends State<FamilyGateScreen> {
  final _uid = TextEditingController();
  bool _busy = false;

  Future<void> _call(Map<String, dynamic> data) async {
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('setFamilyStageFlag')
          .call(data);
    } catch (e) {
      if (mounted) _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _toggleSignOff(bool on) async {
    if (on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: T.panel,
          title: Text('Confirm CA / legal sign-off',
              style: T.fraunces(19, color: T.ivory)),
          content: Text(
              'This opens the Family Stage — guardian contact exchange and the '
              'wali digest — to ALL users, not just testers. Only do this after '
              'CA and legal have reviewed it.',
              style: T.inter(13.5, color: T.muted, height: 1.6)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: T.inter(13.5, color: T.muted))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: T.approve),
                child: Text('Sign off & open to all',
                    style: T.inter(13.5, color: T.ivory))),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _call({'legalSignedOff': on});
  }

  @override
  Widget build(BuildContext context) {
    final stream =
        FirebaseFirestore.instance.doc('config/featureFlags').snapshots();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final fs = (snap.data!.data()?['familyStage'] as Map?) ?? const {};
        final signedOff = fs['legalSignedOff'] == true;
        final testers =
            ((fs['testerUids'] as List?) ?? const []).map((e) => '$e').toList();

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---- sign-off state ----
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: T.panel,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: signedOff
                                ? T.approve.withOpacity(.6)
                                : T.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text('CA / legal sign-off',
                                  style: T.fraunces(18, color: T.ivory)),
                            ),
                            Switch(
                              value: signedOff,
                              activeColor: T.approve,
                              onChanged:
                                  _busy ? null : (v) => _toggleSignOff(v),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Text(
                            signedOff
                                ? 'Signed off — the Family Stage is OPEN TO ALL '
                                    'users.'
                                : 'Locked — the Family Stage runs only for the '
                                    'testers listed below.',
                            style: T.inter(13, color: T.muted, height: 1.6),
                          ),
                          if (signedOff && fs['signedOffBy'] != null) ...[
                            const SizedBox(height: 6),
                            Text('by ${fs['signedOffBy']}',
                                style: T.inter(11.5, color: T.muted)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ---- tester allowlist ----
                    Text('CLOSED-TESTING ALLOWLIST',
                        style: T.inter(11,
                            weight: FontWeight.w700, color: T.gold)),
                    const SizedBox(height: 4),
                    Text(
                        'These UIDs can use the Family Stage while it is locked.',
                        style: T.inter(12.5, color: T.muted)),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _uid,
                          style: T.inter(13.5, color: T.ivory),
                          decoration: InputDecoration(
                            hintText: 'Add a tester UID',
                            hintStyle: T.inter(13.5, color: T.muted),
                            enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: T.hairline)),
                            focusedBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: T.gold)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final u = _uid.text.trim();
                                if (u.isEmpty) return;
                                await _call({'addTester': u});
                                _uid.clear();
                              },
                        style: FilledButton.styleFrom(
                            backgroundColor: T.gold, foregroundColor: T.ctaText),
                        child: Text('Add',
                            style: T.inter(13.5, weight: FontWeight.w600)),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    if (testers.isEmpty)
                      Text('No testers yet — the feature is fully locked.',
                          style: T.inter(13, color: T.muted))
                    else
                      ...testers.map((u) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                            decoration: BoxDecoration(
                              color: T.panel,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: T.hairline),
                            ),
                            child: Row(children: [
                              Expanded(
                                child: Text(u,
                                    style: T.inter(13, color: T.ivory)),
                              ),
                              IconButton(
                                onPressed: _busy
                                    ? null
                                    : () => _call({'removeTester': u}),
                                icon: Icon(Icons.close,
                                    size: 18, color: T.muted),
                                tooltip: 'Remove',
                              ),
                            ]),
                          )),
                    if (_busy) ...[
                      const SizedBox(height: 18),
                      const Center(
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

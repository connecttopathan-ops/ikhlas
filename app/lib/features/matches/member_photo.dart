import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/widgets.dart';

/// Renders a member's photo through the server pipeline (permission +
/// blur + watermark). Originals are never fetched directly; if the
/// server denies (no relationship, or a privacy mode that hides), we
/// fall back to the girih silhouette — never a broken image.
class MemberPhoto extends StatefulWidget {
  final String ownerUid;
  final int index;
  final double width;
  final double height;
  final double radius;
  const MemberPhoto({
    super.key,
    required this.ownerUid,
    this.index = 0,
    required this.width,
    required this.height,
    this.radius = 10,
  });

  // The deployed HTTPS function (asia-south1).
  static const _base =
      'https://asia-south1-ikhlas-caecf.cloudfunctions.net/photo';

  @override
  State<MemberPhoto> createState() => _MemberPhotoState();
}

class _MemberPhotoState extends State<MemberPhoto> {
  Future<String?>? _token;

  @override
  void initState() {
    super.initState();
    _token = FirebaseAuth.instance.currentUser?.getIdToken();
  }

  Widget _silhouette() => Container(
        width: widget.width,
        height: widget.height,
        alignment: Alignment.center,
        child: GirihMark(size: widget.width * .5, opacity: .55),
      );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: FutureBuilder<String?>(
        future: _token,
        builder: (context, snap) {
          if (!snap.hasData || snap.data == null) return _silhouette();
          final url =
              '${MemberPhoto._base}?owner=${widget.ownerUid}&idx=${widget.index}';
          return Image.network(
            url,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.cover,
            headers: {'Authorization': 'Bearer ${snap.data}'},
            errorBuilder: (_, __, ___) => _silhouette(),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : _silhouette(),
          );
        },
      ),
    );
  }
}

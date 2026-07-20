import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../matches/member_photo.dart';

/// A round profile photo for chat surfaces (list + header), WhatsApp-style.
///
/// Shows the person's photo when it is actually viewable to me — public, or
/// (since we're matched here) an on_mutual_blur photo, or an on_mutual_hidden
/// photo they've revealed. Otherwise it falls back to their initial on a soft
/// gold disc. Uses the same cache-divergence rule as the chat profile so a
/// matched/revealed photo doesn't reuse the batch's blurred bytes.
class ChatAvatar extends StatelessWidget {
  final String ownerUid;
  final Map<String, dynamic>? profile;
  final bool photoRevealed;
  final double size;
  const ChatAvatar({
    super.key,
    required this.ownerUid,
    required this.profile,
    this.photoRevealed = false,
    this.size = 44,
  });

  bool get _viewable {
    final p = profile ?? const {};
    if (p['hasPhotos'] != true) return false;
    switch (p['photoVisibility']) {
      case 'public':
      case 'visible':
      case 'on_mutual_blur':
      case 'blur_until_match':
        return true; // matched here → blur resolves to clear
      case 'on_mutual_hidden':
      case 'request_only':
        return photoRevealed;
      default:
        return false;
    }
  }

  String? get _bust {
    switch (profile?['photoVisibility']) {
      case 'on_mutual_hidden':
      case 'request_only':
        return photoRevealed ? 'chatR' : 'chat';
      case 'on_mutual_blur':
      case 'blur_until_match':
        return 'chat';
      default:
        return null; // public — reuse the batch cache
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_viewable) {
      return MemberPhoto(
        ownerUid: ownerUid,
        width: size,
        height: size,
        radius: size / 2,
        cacheBust: _bust,
      );
    }
    final name = (profile?['displayName'] as String?)?.trim() ?? '';
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '·';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: DarkTokens.gold.withValues(alpha: .12),
        border: Border.all(color: DarkTokens.hairline(.4)),
      ),
      alignment: Alignment.center,
      child: Text(initial,
          style: AppType.fraunces(size * .38, color: DarkTokens.gold)),
    );
  }
}

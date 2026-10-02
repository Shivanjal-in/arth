// Edit your profile: photo (uploaded to Cloudinary via a signed ticket),
// name and a short line about what you read. Also where you sign out.

import 'dart:async';
import 'dart:io';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/account.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/features/account/account_card.dart';
import 'package:arth/features/settings/settings_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  bool _uploading = false;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _snack(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    final t = ref.read(stringsProvider);
    setState(() => _saving = true);
    try {
      await ref.read(accountProvider.notifier).updateProfile(displayName: _name.text.trim(), bio: _bio.text.trim());
      if (mounted) _snack(t.profileSaved);
    } on ApiFailure catch (e) {
      if (mounted) _snack(t.errorFor(e.code, e.message));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPhoto() async {
    final t = ref.read(stringsProvider);
    // 1024px is plenty: Cloudinary crops to a 512px square on the face.
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 88);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      await ref.read(accountProvider.notifier).setPhoto(picked.path);
    } on ApiFailure {
      if (mounted) _snack(t.photoFailed);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _testPush() async {
    final t = ref.read(stringsProvider);
    try {
      // Make sure this phone is registered (permission may just have been granted).
      await ref.read(pushServiceProvider)?.register();
      final r = await ref.read(apiClientProvider).testPush();
      if (mounted) _snack(t.testNotificationSent(r.devices));
    } on ApiFailure catch (e) {
      if (mounted) _snack(t.errorFor(e.code, e.message));
    }
  }

  Future<void> _signOut() async {
    final t = ref.read(stringsProvider);
    final c = context.colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        content: Text(t.signOutConfirm, style: uiBody(hindi: t.isHindi, color: c.ink)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.signOut)),
        ],
      ),
    );
    if (ok != true) return;
    // Push anything unsynced first, so nothing is left only on this phone.
    await ref.read(syncProvider.notifier).run();
    // Stop this phone getting the account's notifications (needs the session).
    await ref.read(pushServiceProvider)?.unregister();
    await ref.read(authServiceProvider)?.signOut();
    if (mounted) await Navigator.of(context).maybePop();
  }

  /// Deletes the account (as the stores require, from inside the app). The
  /// server forgets everything it keeps; this phone then signs out without
  /// asking the API for anything more, which it would now refuse.
  Future<void> _deleteAccount() async {
    final t = ref.read(stringsProvider);
    final c = context.colors;
    final scale = ref.read(settingsProvider).hindiScale;
    final paid = (ref.read(accountProvider).valueOrNull?.tier ?? Tier.free) != Tier.free;
    final store = Platform.isIOS ? 'the App Store' : 'Google Play';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(t.deleteAccountTitle, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (paid) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.marigold.withValues(alpha: 0.15), border: Border.all(color: c.ink, width: 1.5)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.deleteAccountSubscription(store), style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 14)),
                      TextButton(
                        onPressed: () async {
                          final url = await ref.read(billingProvider).managementUrl() ??
                              (Platform.isIOS ? 'https://apps.apple.com/account/subscriptions' : 'https://play.google.com/store/account/subscriptions');
                          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                        },
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: c.accent),
                        child: Text(t.manageSubscription),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text(t.deleteAccountBody, style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 14.5)),
              const SizedBox(height: 8),
              Text(t.deleteAccountLocal, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 13.5)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: Text(t.deleteForever),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).deleteAccount();
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.errorFor(e.code, e.message))));
      }
      return;
    }
    await ref.read(pushServiceProvider)?.forgetLocally();
    await ref.read(authServiceProvider)?.signOut();
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.accountDeleted)));
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final account = ref.watch(accountProvider);
    final a = account.valueOrNull;
    if (a != null && !_loaded) {
      _loaded = true;
      _name.text = a.displayName;
      _bio.text = a.bio;
    }
    final label = uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale);

    return Scaffold(
      appBar: AppBar(title: Text(t.profile)),
      body: a == null
          ? Center(
              child: account.hasError
                  ? Text(t.somethingWrong, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale))
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
              children: [
                Center(
                  child: Stack(
                    children: [
                      Avatar(name: a.label, url: a.photoUrl, size: 112),
                      if (_uploading)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
                            child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                          ),
                        ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: c.accent,
                          shape: CircleBorder(side: BorderSide(color: c.paper, width: 3)),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _uploading ? null : _pickPhoto,
                            child: Padding(padding: const EdgeInsets.all(9), child: Icon(Icons.photo_camera_outlined, size: 20, color: c.onAccent)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (a.photoUrl != null)
                  Center(
                    child: TextButton(
                      onPressed: _uploading ? null : () => unawaited(ref.read(accountProvider.notifier).removePhoto()),
                      style: TextButton.styleFrom(foregroundColor: c.inkMuted),
                      child: Text(t.removePhoto),
                    ),
                  )
                else
                  const SizedBox(height: 16),
                const SizedBox(height: 8),
                Text(t.displayName, style: label),
                TextField(
                  controller: _name,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  style: EnglishText.body(c.ink, size: 18),
                  decoration: const InputDecoration(counterText: ''),
                ),
                const SizedBox(height: 20),
                Text(t.bio, style: label),
                TextField(
                  controller: _bio,
                  maxLength: 280,
                  minLines: 2,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: EnglishText.body(c.ink, size: 16),
                  decoration: InputDecoration(hintText: t.bioHint, hintStyle: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 15)),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _saving || _name.text.trim().isEmpty ? null : _save,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: Text(t.saveProfile),
                ),
                const SizedBox(height: 28),
                Divider(color: c.rule),
                const SizedBox(height: 8),
                for (final (icon, value) in [(Icons.mail_outline_rounded, a.email), (Icons.phone_outlined, a.phone)])
                  if (value != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(icon, size: 18, color: c.inkMuted),
                          const SizedBox(width: 12),
                          Text(value, style: EnglishText.body(c.ink)),
                        ],
                      ),
                    ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.workspace_premium_outlined, size: 18, color: c.inkMuted),
                      const SizedBox(width: 12),
                      Text(tierLabel(a.tier, t), style: EnglishText.body(c.ink)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SettingsSwitch(
                  title: t.reviewReminders,
                  subtitle: t.reviewRemindersHelp,
                  value: a.reviewReminders,
                  onChanged: (v) => unawaited(ref.read(accountProvider.notifier).setReviewReminders(on: v)),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _testPush,
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    icon: const Icon(Icons.notifications_active_outlined, size: 18),
                    label: Text(t.testNotification),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: Icon(Icons.logout_rounded, color: c.accent),
                  label: Text(t.signOut, style: uiLabel(hindi: t.isHindi, color: c.accent, scale: scale)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), side: BorderSide(color: c.rule)),
                ),
                const SizedBox(height: 28),
                Center(
                  child: TextButton.icon(
                    onPressed: _saving ? null : _deleteAccount,
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    icon: const Icon(Icons.delete_forever_outlined, size: 18),
                    label: Text(t.deleteAccount, style: uiLabel(hindi: t.isHindi, color: c.accent, scale: scale).copyWith(fontSize: 13.5)),
                  ),
                ),
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../local_db.dart';
import '../responsive.dart';
import '../services/app_strings.dart';
import 'notification_service.dart';
import 'package:google_sign_in/google_sign_in.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _userEmail = "";
  String _displayName = "";
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    final name = await LocalDB.instance.getDisplayName();
    final notifEnabled = await NotificationService().areNotificationsEnabled();
    if (mounted) {
      setState(() {
        _userEmail = user?.email ?? S.noEmail;
        _displayName = name ?? '';
        _notificationsEnabled = notifEnabled;
      });
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _displayName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardColor,
        title: Text(S.displayName, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: S.enterName,
            hintStyle: TextStyle(color: Colors.grey.shade600),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade700)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.cancel, style: const TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(S.save, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result != null) {
      await LocalDB.instance.setDisplayName(result);
      if (mounted) setState(() => _displayName = result);
    }
  }

  void _openFeedback() {
    showDialog(
      context: context,
      builder: (_) => const _FeedbackDialog(),
    );
  }

  Future<void> _signOut() async {
    try {
      await GoogleSignIn().signOut();
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${S.errorSigningOut} $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // TITLE
                    Padding(
                      padding: EdgeInsets.only(top: r.spacing(16), bottom: r.spacing(12)),
                      child: Center(
                        child: Text(S.profileTitle, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: r.fontSize(18), letterSpacing: 1.5)),
                      ),
                    ),

            // ── HEADER: Avatar + Name + Email ──
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: const CircleAvatar(
                radius: 38,
                backgroundColor: AppColors.cardColor,
                child: Icon(Icons.person, size: 38, color: Colors.white),
              ),
            ),

            const SizedBox(height: 10),

            // Display name (tappable to edit)
            GestureDetector(
              onTap: _editName,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _displayName.isEmpty ? S.student : _displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.edit, color: Colors.grey.shade600, size: 14),
                ],
              ),
            ),

            const SizedBox(height: 2),

            // Email
            Text(_userEmail, style: const TextStyle(color: Colors.grey, fontSize: 13)),

            // Student label
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                S.student,
                style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),

            const SizedBox(height: 20),

            // ── ACCOUNT SECTION ──
            _sectionHeader(S.account),
            const SizedBox(height: 6),

            // Language toggle
            _buildLanguageOption(),

            // Notifications toggle
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.notifications_outlined, color: AppColors.primary),
                title: Text(S.notifications, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                trailing: Switch(
                  value: _notificationsEnabled,
                  activeColor: AppColors.primary,
                  onChanged: (value) async {
                    await NotificationService().openSettings();
                    final enabled = await NotificationService().areNotificationsEnabled();
                    if (mounted) setState(() => _notificationsEnabled = enabled);
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── HELP CENTER SECTION ──
            _sectionHeader(S.helpCenter),
            const SizedBox(height: 6),

            Container(
              decoration: BoxDecoration(
                color: AppColors.cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.feedback_outlined, color: AppColors.primary),
                title: Text(S.contactDeveloper, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(S.contactMessage, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 14),
                onTap: _openFeedback,
              ),
            ),

            const Spacer(),

            // ── LOGOUT ──
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: _signOut,
                child: Text(
                  S.logOut,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),

            const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildLanguageOption() {
    final isGreek = S.locale == 'el';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.language, color: AppColors.primary),
        title: Text(S.language, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isGreek ? '🇬🇷 Ελ' : '🇬🇧 En',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.swap_horiz, color: AppColors.primary, size: 18),
            ],
          ),
        ),
        onTap: () async {
          await S.setLocale(isGreek ? 'en' : 'el');
        },
      ),
    );
  }
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final msg = _controller.text.trim();
    if (msg.isEmpty) return;
    setState(() => _sending = true);
    try {
      await Supabase.instance.client.from('feedback').insert({
        'user_id': Supabase.instance.client.auth.currentUser?.id,
        'message': msg,
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.feedbackSent)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send feedback')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardColor,
      title: Text(S.contactDeveloper, style: const TextStyle(color: Colors.white)),
      content: TextField(
        controller: _controller,
        maxLines: 5,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: S.feedbackHint,
          hintStyle: TextStyle(color: Colors.grey.shade600),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade700),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.primary),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: Text(S.cancel, style: const TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: _sending ? null : _submit,
          child: _sending
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(S.send, style: const TextStyle(color: AppColors.primary)),
        ),
      ],
    );
  }
}

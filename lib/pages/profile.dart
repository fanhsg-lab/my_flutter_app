import 'package:flutter/material.dart';
import 'package:heroicons/heroicons.dart';
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _FeedbackSheet(),
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
                child: HeroIcon(HeroIcons.user, size: 38, color: Colors.white, style: HeroIconStyle.outline),
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
                  HeroIcon(HeroIcons.pencil, color: Colors.grey.shade600, size: 14, style: HeroIconStyle.outline),
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
                leading: const HeroIcon(HeroIcons.bell, color: AppColors.primary, style: HeroIconStyle.outline),
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
                leading: const HeroIcon(HeroIcons.chatBubbleLeftRight, color: AppColors.primary, style: HeroIconStyle.outline),
                title: Text(S.contactDeveloper, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(S.contactMessage, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                trailing: const HeroIcon(HeroIcons.chevronRight, color: Colors.grey, size: 14, style: HeroIconStyle.outline),
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
        leading: const HeroIcon(HeroIcons.language, color: AppColors.primary, style: HeroIconStyle.outline),
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
              const HeroIcon(HeroIcons.arrowsRightLeft, color: AppColors.primary, size: 18, style: HeroIconStyle.outline),
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

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet();

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _controller = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final msg = _controller.text.trim();
    if (msg.isEmpty) return;
    setState(() { _sending = true; _error = null; });
    try {
      await Supabase.instance.client.from('feedback').insert({
        'user_id': Supabase.instance.client.auth.currentUser?.id,
        'message': msg,
      });
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() { _sending = false; _sent = true; });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _sending = false; _error = 'Failed to send. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: _sent ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildSuccess() {
    return Padding(
      key: const ValueKey('success'),
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.15),
            ),
            child: const HeroIcon(HeroIcons.check, size: 48, color: AppColors.primary, style: HeroIconStyle.solid),
          ),
          const SizedBox(height: 20),
          Text(S.feedbackSent, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(S.contactMessage, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final charCount = _controller.text.length;
    return Padding(
      key: const ValueKey('form'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade700, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),

          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const HeroIcon(HeroIcons.chatBubbleLeftRight, size: 22, color: AppColors.primary, style: HeroIconStyle.solid),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.contactDeveloper, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(S.contactMessage, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.grey.shade800, shape: BoxShape.circle),
                  child: const HeroIcon(HeroIcons.xMark, size: 16, color: Colors.grey, style: HeroIconStyle.solid),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Text field
          TextField(
            controller: _controller,
            maxLines: 6,
            maxLength: 500,
            autofocus: false,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: S.feedbackHint,
              hintStyle: TextStyle(color: Colors.grey.shade600),
              counterText: '',
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          const SizedBox(height: 8),

          // Character count
          Align(
            alignment: Alignment.centerRight,
            child: Text('$charCount / 500', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ),

          // Error message
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],

          const SizedBox(height: 16),

          // Send button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _sending || _controller.text.trim().isEmpty ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withOpacity(0.3),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _sending
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                  : Text(S.send, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

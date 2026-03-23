import 'package:flutter/material.dart';
import 'package:heroicons/heroicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../local_db.dart';
import '../responsive.dart';
import '../services/app_strings.dart';
import 'notification_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/subscription_service.dart';

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
      SubscriptionService.instance.dispose();
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

            // ── SUBSCRIPTION SECTION ──
            _sectionHeader(S.subscription),
            const SizedBox(height: 6),
            _buildSubscriptionCard(),

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

            // TODO: unhide when ready
            // const SizedBox(height: 8),
            // Container(
            //   decoration: BoxDecoration(color: AppColors.cardColor, borderRadius: BorderRadius.circular(12)),
            //   child: ListTile(
            //     leading: const HeroIcon(HeroIcons.questionMarkCircle, color: AppColors.primary, style: HeroIconStyle.outline),
            //     title: Text(S.howItWorks, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            //     subtitle: Text(S.howItWorksSubtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
            //     trailing: const HeroIcon(HeroIcons.chevronRight, color: Colors.grey, size: 14, style: HeroIconStyle.outline),
            //     onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _HowItWorksPage())),
            //   ),
            // ),

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

  Widget _buildSubscriptionCard() {
    return ValueListenableBuilder<SubscriptionState>(
      valueListenable: SubscriptionService.instance.state,
      builder: (context, subState, _) {
        String statusText;
        Color statusColor;

        switch (subState.access) {
          case AccessLevel.trial:
            statusText = '${S.freeTrialDaysLeft}: ${S.trialDaysN(subState.trialDaysLeft)}';
            statusColor = AppColors.primary;
          case AccessLevel.subscribed:
            if (subState.expiresAt != null) {
              statusText = '${S.renewsOn} ${DateFormat.yMMMd().format(subState.expiresAt!)}';
            } else {
              statusText = S.active;
            }
            statusColor = Colors.green;
          case AccessLevel.locked:
            statusText = S.expired;
            statusColor = Colors.redAccent;
        }

        return Container(
          decoration: BoxDecoration(
            color: AppColors.cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            dense: true,
            leading: const HeroIcon(HeroIcons.sparkles, color: AppColors.primary, style: HeroIconStyle.solid),
            title: Text(S.palabraPremium, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text(statusText, style: TextStyle(color: statusColor, fontSize: 12)),
            trailing: const HeroIcon(HeroIcons.chevronRight, color: Colors.grey, size: 14, style: HeroIconStyle.outline),
            onTap: () => _showSubscriptionSheet(subState),
          ),
        );
      },
    );
  }

  void _showSubscriptionSheet(SubscriptionState subState) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubscriptionSheet(subState: subState),
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
    return SafeArea(
      child: SingleChildScrollView(
      key: const ValueKey('form'),
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 24),
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
      ),
    );
  }
}

// ── SUBSCRIPTION BOTTOM SHEET ──

class _SubscriptionSheet extends StatefulWidget {
  final SubscriptionState subState;
  const _SubscriptionSheet({required this.subState});

  @override
  State<_SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends State<_SubscriptionSheet> {
  bool _purchasing = false;
  String? _selectedProduct;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade700, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const HeroIcon(HeroIcons.sparkles, size: 22, color: AppColors.primary, style: HeroIconStyle.solid),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.palabraPremium, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(_statusLine(), style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
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

            // If subscribed, show manage button
            if (widget.subState.access == AccessLevel.subscribed) ...[
              _buildInfoRow(S.active, widget.subState.expiresAt != null
                  ? '${S.renewsOn} ${DateFormat.yMMMd().format(widget.subState.expiresAt!)}'
                  : S.active),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => launchUrl(
                    Uri.parse('https://play.google.com/store/account/subscriptions'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(S.manageSub, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                ),
              ),
            ],

            // If trial or locked, show subscription options
            if (widget.subState.access != AccessLevel.subscribed) ...[
              Row(
                children: [
                  Expanded(child: _buildPlanCard(S.monthly, _priceFor(kMonthlyProductId, '€1.99'), S.perMonth, kMonthlyProductId)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildPlanCard(S.yearly, _priceFor(kYearlyProductId, '€14.99'), S.perYear, kYearlyProductId, badge: S.save33)),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _purchasing || _selectedProduct == null ? null : _onSubscribe,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withOpacity(0.3),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _purchasing
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                      : Text(S.subscribe, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Restore purchases
            TextButton(
              onPressed: _purchasing ? null : _onRestore,
              child: Text(S.restorePurchases, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ),
          ],
        ),
        ),
      ),
    );
  }

  String _statusLine() {
    switch (widget.subState.access) {
      case AccessLevel.trial:
        return '${S.freeTrialDaysLeft}: ${S.trialDaysN(widget.subState.trialDaysLeft)}';
      case AccessLevel.subscribed:
        return S.active;
      case AccessLevel.locked:
        return S.expired;
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildPlanCard(String title, String price, String period, String productId, {String? badge}) {
    final isSelected = _selectedProduct == productId;
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? AppColors.primary : Colors.white10,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(price, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          Text(period, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );

    return GestureDetector(
      onTap: () => setState(() => _selectedProduct = productId),
      child: badge != null
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                card,
                Positioned(
                  top: -10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : card,
    );
  }

  String _priceFor(String productId, String fallback) {
    return fallback;
  }

  Future<void> _onSubscribe() async {
    if (_selectedProduct == null) return;
    setState(() => _purchasing = true);
    try {
      await SubscriptionService.instance.purchase(_selectedProduct!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _onRestore() async {
    setState(() => _purchasing = true);
    try {
      await SubscriptionService.instance.restorePurchases();
      await Future.delayed(const Duration(seconds: 2));
      await SubscriptionService.instance.refreshStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }
}

// ── HOW IT WORKS PAGE ──

class _HIWSection {
  final String title;
  const _HIWSection(this.title);
}

class _HIWQA {
  final String q, a;
  const _HIWQA(this.q, this.a);
}

class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage();

  List<Object> _buildItems(bool isEl) {
    if (isEl) {
      return [
        const _HIWSection('ΚΑΤΑΣΤΑΣΗ ΛΕΞΕΩΝ'),
        const _HIWQA(
          'Τι σημαίνουν Κατακτημένες, Επανάληψη και Νέες;',
          'Νέες: δεν έχουν μελετηθεί ακόμα.\n'
          'Επανάληψη: τις μαθαίνεις ενεργά — ξεκίνησες αλλά δεν τις έχεις κατακτήσει.\n'
          'Κατακτημένες: έχουν απαντηθεί σωστά αρκετές φορές και είναι εδραιωμένες στη μνήμη σου.',
        ),
        const _HIWQA(
          'Τι σημαίνουν τα χρώματα των λέξεων;',
          'Πορτοκαλί → Κατακτημένη\n'
          'Σκούρο πορτοκαλί → Εκμάθηση (Επανάληψη)\n'
          'Γκρι → Νέα (δεν έχει μελετηθεί ακόμα)',
        ),
        const _HIWQA(
          'Τι σημαίνει το ποσοστό σε κάθε λέξη;',
          'Δείχνει την ακρίβειά σου — πόσες φορές απάντησες σωστά από το συνολικό αριθμό προσπαθειών. '
          '80% σημαίνει 8 στις 10 σωστές απαντήσεις.',
        ),
        const _HIWSection('ΣΤΑΤΙΣΤΙΚΑ'),
        const _HIWQA(
          'Τι είναι η Ισχύς Μνήμης;',
          'Ένα ποσοστό 0–100% που δείχνει πόσο καλά θυμάσαι μια λέξη. Ανεβαίνει με κάθε σωστή απάντηση '
          'και πέφτει σταδιακά αν δεν επαναλαμβάνεις.',
        ),
        const _HIWQA(
          'Τι δείχνει το γράφημα Δραστηριότητας;',
          'Τον αριθμό λέξεων που εξασκήθηκες κάθε μέρα. Πιο ψηλές μπάρες σημαίνουν περισσότερη εξάσκηση εκείνη τη μέρα.',
        ),
        const _HIWQA(
          'Τι δείχνει το γράφημα Διατήρησης;',
          'Το συνολικό ποσοστό διατήρησης — ο μέσος όρος ισχύος μνήμης για όλες τις λέξεις που έχεις μελετήσει.',
        ),
        const _HIWQA(
          'Τι είναι η Ταχύτητα;',
          'Ο μέσος αριθμός νέων λέξεων που μαθαίνεις κάθε μέρα. Μεγαλύτερος αριθμός σημαίνει ότι προχωράς πιο γρήγορα.',
        ),
        const _HIWQA(
          'Τι είναι η Πρόβλεψη;',
          'Λέξεις που έχουν προγραμματιστεί για επανάληψη τις επόμενες μέρες. '
          '"Καθυστερημένες" σημαίνει λέξεις που ήταν για επανάληψη αλλά δεν επαναλήφθηκαν ακόμα.',
        ),
        const _HIWQA(
          'Τι είναι το Σερί;',
          'Ο αριθμός των συνεχόμενων ημερών που εξασκήθηκες. Χάνεται αν παραλείψεις μία μέρα.',
        ),
        const _HIWSection('ΛΕΙΤΟΥΡΓΙΑ ΤΕΣΤ'),
        const _HIWQA(
          'Πώς λειτουργεί η Λειτουργία Τεστ;',
          'Εμφανίζεται μια λέξη και επιλέγεις από 4 φυσαλίδες απαντήσεων. '
          'Κάθε απάντηση ενημερώνει αυτόματα την ισχύ μνήμης της λέξης. '
          'Η συνεδρία τελειώνει όταν εμφανιστούν όλες οι λέξεις.',
        ),
        const _HIWQA(
          'Ποια η διαφορά Επανάληψης και Εξάσκησης;',
          'Επανάληψη: εμφανίζονται μόνο λέξεις που είναι προγραμματισμένες (βάσει spaced repetition).\n'
          'Εξάσκηση: εμφανίζονται όλες οι λέξεις του μαθήματος ανεξάρτητα από το πρόγραμμα.',
        ),
        const _HIWQA(
          'Τι είναι το spaced repetition;',
          'Μέθοδος μάθησης που προγραμματίζει επαναλήψεις σε αυξανόμενα χρονικά διαστήματα. '
          'Λέξεις που ξέρεις καλά εμφανίζονται σπανιότερα, ενώ δύσκολες λέξεις εμφανίζονται πιο συχνά. '
          'Έτσι μεγιστοποιείται η διατήρηση με λιγότερο χρόνο μελέτης.',
        ),
      ];
    }

    return [
      const _HIWSection('WORD STATUS'),
      const _HIWQA(
        'What do Mastered, Review, and New mean?',
        'New: not yet studied.\n'
        'Review: actively being learned — you\'ve started but haven\'t mastered it yet.\n'
        'Mastered: answered correctly enough times to be deeply memorized.',
      ),
      const _HIWQA(
        'What do the word colors mean?',
        'Orange → Mastered\n'
        'Deep orange → Learning (Review)\n'
        'Grey → New (not yet studied)',
      ),
      const _HIWQA(
        'What does the percentage on each word mean?',
        'It shows your accuracy rate — how often you answered the word correctly out of all your attempts. '
        '80% means 8 out of 10 answers were correct.',
      ),
      const _HIWSection('STATS'),
      const _HIWQA(
        'What is Memory Strength?',
        'A 0–100% score showing how well a word is retained in memory. '
        'It rises when you answer correctly and gradually drops over time if you don\'t review.',
      ),
      const _HIWQA(
        'What does the Activity graph show?',
        'The number of words you practiced each day. Taller bars mean more practice that day. '
        'Use it to track how consistent you are.',
      ),
      const _HIWQA(
        'What does the Retention graph show?',
        'Your overall retention percentage — the average memory strength across all words you\'ve studied.',
      ),
      const _HIWQA(
        'What is Velocity?',
        'The average number of new words you learn per day. A higher number means you\'re progressing faster.',
      ),
      const _HIWQA(
        'What is the Forecast?',
        'Words scheduled for review in the coming days, broken down by day (Today, Tomorrow, +2d, etc.). '
        '"Late" means words that were due for review but haven\'t been practiced yet.',
      ),
      const _HIWQA(
        'What is the Streak?',
        'The number of consecutive days you\'ve practiced. Study every day to keep it — missing a day resets it to zero.',
      ),
      const _HIWSection('TEST MODE'),
      const _HIWQA(
        'How does Test Mode work?',
        'A word appears on screen and you choose from 4 answer bubbles — tap the correct translation. '
        'Each answer automatically updates the word\'s memory strength. '
        'The session ends after all words have been shown.',
      ),
      const _HIWQA(
        'What is the difference between Review Mode and Practice Mode?',
        'Review Mode shows only words scheduled for review (based on spaced repetition).\n'
        'Practice Mode shows all words in the lesson regardless of their review schedule.',
      ),
      const _HIWQA(
        'What is spaced repetition?',
        'A learning method that schedules reviews at increasing intervals. '
        'Words you know well are shown less often; words you struggle with are shown more frequently. '
        'This maximizes retention with less study time.',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isEl = S.locale == 'el';
    final items = _buildItems(isEl);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const HeroIcon(HeroIcons.arrowLeft, color: Colors.white, size: 22, style: HeroIconStyle.outline),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(S.howItWorks, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          if (item is _HIWSection) {
            return Padding(
              padding: EdgeInsets.only(top: index == 0 ? 4 : 20, bottom: 8),
              child: Text(
                item.title,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            );
          }
          final qa = item as _HIWQA;
          return _QAItem(question: qa.q, answer: qa.a);
        },
      ),
    );
  }
}

class _QAItem extends StatelessWidget {
  final String question;
  final String answer;

  const _QAItem({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            leading: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text(
                  '?',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
            title: Text(
              question,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            iconColor: AppColors.primary,
            collapsedIconColor: Colors.grey,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  answer,
                  style: TextStyle(color: Colors.grey.shade300, fontSize: 13, height: 1.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:heroicons/heroicons.dart';
import '../theme.dart';
import '../responsive.dart';
import '../services/app_strings.dart';
import '../services/subscription_service.dart';

class PaywallOverlay extends StatefulWidget {
  const PaywallOverlay({super.key});

  @override
  State<PaywallOverlay> createState() => _PaywallOverlayState();
}

class _PaywallOverlayState extends State<PaywallOverlay> {
  bool _purchasing = false;
  String? _selectedProduct;

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    return Container(
      color: AppColors.background.withOpacity(0.95),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: r.spacing(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lock icon
                Container(
                  padding: EdgeInsets.all(r.spacing(20)),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.15),
                  ),
                  child: HeroIcon(
                    HeroIcons.lockClosed,
                    size: r.iconSize(48),
                    color: AppColors.primary,
                    style: HeroIconStyle.solid,
                  ),
                ),
                SizedBox(height: r.spacing(24)),

                // Title
                Text(
                  S.trialExpired,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: r.fontSize(22),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: r.spacing(8)),

                // Subtitle
                Text(
                  S.unlockLearning,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: r.fontSize(14),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: r.spacing(32)),

                // Subscription cards
                Row(
                  children: [
                    Expanded(child: _buildPlanCard(
                      title: S.monthly,
                      price: '\$4.99',
                      period: S.perMonth,
                      productId: kMonthlyProductId,
                      r: r,
                    )),
                    SizedBox(width: r.spacing(12)),
                    Expanded(child: _buildPlanCard(
                      title: S.yearly,
                      price: '\$39.99',
                      period: S.perYear,
                      productId: kYearlyProductId,
                      badge: S.save33,
                      r: r,
                    )),
                  ],
                ),
                SizedBox(height: r.spacing(24)),

                // Subscribe button
                SizedBox(
                  width: double.infinity,
                  height: r.spacing(52),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(r.radius(14)),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _purchasing || _selectedProduct == null
                        ? null
                        : () => _onSubscribe(),
                    child: _purchasing
                        ? SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            S.subscribe,
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: r.fontSize(16),
                            ),
                          ),
                  ),
                ),
                SizedBox(height: r.spacing(16)),

                // Restore purchases
                TextButton(
                  onPressed: _purchasing ? null : _onRestore,
                  child: Text(
                    S.restorePurchases,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: r.fontSize(13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required String title,
    required String price,
    required String period,
    required String productId,
    required Responsive r,
    String? badge,
  }) {
    final isSelected = _selectedProduct == productId;
    return GestureDetector(
      onTap: () => setState(() => _selectedProduct = productId),
      child: Container(
        padding: EdgeInsets.all(r.spacing(16)),
        decoration: BoxDecoration(
          color: AppColors.cardColor,
          borderRadius: BorderRadius.circular(r.radius(14)),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.white10,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            if (badge != null) ...[
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: r.spacing(8),
                  vertical: r.spacing(3),
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(r.radius(6)),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: r.fontSize(10),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(height: r.spacing(8)),
            ],
            Text(
              title,
              style: TextStyle(
                color: Colors.grey,
                fontSize: r.fontSize(12),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: r.spacing(6)),
            Text(
              price,
              style: TextStyle(
                color: Colors.white,
                fontSize: r.fontSize(24),
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              period,
              style: TextStyle(
                color: Colors.grey,
                fontSize: r.fontSize(11),
              ),
            ),
          ],
        ),
      ),
    );
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
      // Give time for purchase stream to process
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

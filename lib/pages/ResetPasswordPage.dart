import 'package:flutter/material.dart';
import 'package:heroicons/heroicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';

class ResetPasswordPage extends StatefulWidget {
  final String email; // We pass the email from the previous screen
  const ResetPasswordPage({super.key, required this.email});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _verifyAndReset() async {
    final token = _tokenController.text.trim();
    final newPassword = _passwordController.text.trim();

    if (token.isEmpty || newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid Token or Password too short")));
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 1. Verify the OTP (Token)
      final response = await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.recovery,
        token: token,
        email: widget.email,
      );

      // 2. If verification works, update the password
      if (response.session != null) {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: newPassword),
        );
        
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password Updated! Logging in...")));
           // Go to Home
           Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Enter Code"), backgroundColor: Colors.transparent),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text("We sent a code to ${widget.email}", style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            
            // Token Field
            _buildTextField("6-Digit Code", HeroIcons.hashtag, _tokenController),
            const SizedBox(height: 15),

            // New Password Field
            _buildTextField("New Password", HeroIcons.lockClosed, _passwordController, isPassword: true),
            
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity, 
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: _isLoading ? null : _verifyAndReset,
                child: _isLoading ? const CircularProgressIndicator() : const Text("RESET PASSWORD", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, HeroIcons icon, TextEditingController c, {bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(color: AppColors.cardColor, borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: c,
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: HeroIcon(icon, color: Colors.grey, style: HeroIconStyle.outline),
          border: InputBorder.none,
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }
}
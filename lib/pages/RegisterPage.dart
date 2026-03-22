import 'dart:io' show Platform;
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:heroicons/heroicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../theme.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  // --- GOOGLE SIGN UP LOGIC (Same as Login) ---
  Future<void> _googleSignUp() async {
    setState(() => _isLoading = true);
    try {
      if (Platform.isIOS) {
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
        );
      } else {
        final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID']!;
        final GoogleSignIn googleSignIn = GoogleSignIn(
          serverClientId: webClientId,
        );

        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          setState(() => _isLoading = false);
          return;
        }

        final googleAuth = await googleUser.authentication;
        final idToken = googleAuth.idToken;
        if (idToken == null) throw 'No ID Token found.';

        await Supabase.instance.client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: googleAuth.accessToken,
        );

        if (mounted) Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (mounted) _showError('Google Sign Up Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _appleSignUp() async {
    setState(() => _isLoading = true);
    try {
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256ofString(rawNonce);

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) throw 'No identity token found.';

      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      if (mounted) Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      if (mounted) _showError('Apple Sign In Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (password != confirm) {
      _showError("Passwords do not match");
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );
      
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black87,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF111214),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mark_email_read_outlined, color: AppColors.primary, size: 32),
                  ),
                  const SizedBox(height: 20),
                  const Text('Check your email', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text('We sent a confirmation link to\n$email', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade400, fontSize: 14, height: 1.5)),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: () { Navigator.pop(ctx); Navigator.of(context).pop(); },
                      child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      try {
                        await Supabase.instance.client.auth.resend(type: OtpType.signup, email: email);
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Email resent! Check your inbox.')),
                        );
                      } catch (e) {
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Failed to resend: ${e.toString()}'), backgroundColor: AppColors.error),
                        );
                      }
                    },
                    child: Text('Resend email', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } on AuthException catch (error) {
      if (mounted) _showError(error.message);
    } catch (error) {
      if (mounted) _showError('Unexpected error occurred');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Create Account,", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                const Text("Sign up to start your journey.", style: TextStyle(fontSize: 16, color: Colors.grey)),
                
                const SizedBox(height: 40),
                
                _buildTextField("Email", HeroIcons.envelope, _emailController, false),
                const SizedBox(height: 20),
                _buildTextField("Password", HeroIcons.lockClosed, _passwordController, true),
                const SizedBox(height: 20),
                _buildTextField("Confirm Password", HeroIcons.shieldCheck, _confirmPasswordController, true),
                
                const SizedBox(height: 40),
                
                // SIGN UP BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 5,
                    ),
                    onPressed: _isLoading ? null : _signUp,
                    child: _isLoading 
                        ? const CircularProgressIndicator(color: Colors.black) 
                        : const Text("SIGN UP", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
                ),

                const SizedBox(height: 20),

                // DIVIDER
                Row(
                  children: const [
                    Expanded(child: Divider(color: Colors.grey)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text("OR", style: TextStyle(color: Colors.grey)),
                    ),
                    Expanded(child: Divider(color: Colors.grey)),
                  ],
                ),

                const SizedBox(height: 20),

                // GOOGLE BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: BorderSide.none,
                    ),
                    onPressed: _isLoading ? null : _googleSignUp,
                    icon: const Icon(Icons.g_mobiledata, color: Colors.black, size: 32),
                    label: const Text("Sign up with Google", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
                ),

                if (Platform.isIOS) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: SignInWithAppleButton(
                      onPressed: _isLoading ? () {} : _appleSignUp,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Already have an account? ", style: TextStyle(color: Colors.grey)),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Text("Login", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, HeroIcons icon, TextEditingController controller, bool isPassword) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      style: const TextStyle(color: Colors.white),
      cursorColor: AppColors.primary,
      decoration: InputDecoration(
        prefixIcon: HeroIcon(icon, color: Colors.grey, style: HeroIconStyle.outline),
        filled: true,
        fillColor: AppColors.cardColor,
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
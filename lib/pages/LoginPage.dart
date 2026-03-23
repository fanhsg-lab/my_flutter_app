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
import 'RegisterPage.dart';
import 'ForgotPasswordPage.dart';
import 'UpdatePasswordPage.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const UpdatePasswordPage()),
          );
        }
      } else if (event == AuthChangeEvent.signedIn) {
        if (mounted) Navigator.of(context).pushReplacementNamed('/home');
      }
    });
  }

  // --- GOOGLE SIGN IN LOGIC ---
  Future<void> _googleSignIn() async {
    setState(() => _isLoading = true);
    try {
      if (Platform.isIOS) {
        // iOS: use OAuth flow (handles nonce automatically)
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
        );
        // Auth state change listener in initState will handle navigation
      } else {
        // Android: use native Google Sign In
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
      if (mounted) _showError('Google Sign In Error: $e');
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

  Future<void> _appleSignIn() async {
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

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    child: const HeroIcon(HeroIcons.academicCap, size: 60, color: AppColors.primary, style: HeroIconStyle.solid),
                  ),
                ),
                const SizedBox(height: 40),

                const Text("Welcome Back,", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                const Text("Sign in to continue learning.", style: TextStyle(fontSize: 16, color: Colors.grey)),
                
                const SizedBox(height: 40),
                
                _buildTextField("Email", HeroIcons.envelope, _emailController, false),
                const SizedBox(height: 20),
                _buildTextField("Password", HeroIcons.lockClosed, _passwordController, true),
                
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ForgotPasswordPage()),
                      );
                    },
                    child: const Text("Forgot Password?", style: TextStyle(color: AppColors.primary)),
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // LOGIN BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 5,
                    ),
                    onPressed: _isLoading ? null : _signIn,
                    child: _isLoading 
                        ? const CircularProgressIndicator(color: Colors.black) 
                        : const Text("LOGIN", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
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

                // GOOGLE BUTTON (Android only)
                if (!Platform.isIOS)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        side: BorderSide.none,
                      ),
                      onPressed: _isLoading ? null : _googleSignIn,
                      icon: const Icon(Icons.g_mobiledata, color: Colors.black, size: 32),
                      label: const Text("Sign in with Google", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                    ),
                  ),

                if (Platform.isIOS) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: SignInWithAppleButton(
                      onPressed: _isLoading ? () {} : _appleSignIn,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("New user? ", style: TextStyle(color: Colors.grey)),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterPage())),
                      child: const Text("Register", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    "Start with a 2-month free trial!",
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ),
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
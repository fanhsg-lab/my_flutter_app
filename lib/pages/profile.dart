import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart'; 
import '../local_db.dart'; 
import 'notification_service.dart'; // Import the service
import 'package:google_sign_in/google_sign_in.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _userEmail = "Loading...";

  @override
  void initState() {
    super.initState();
    _getUserData();
  }

  void _getUserData() {
    final user = Supabase.instance.client.auth.currentUser;
    setState(() {
      _userEmail = user?.email ?? "No Email";
    });
  }

  Future<void> _fixMyApp() async {
    final db = await LocalDB.instance.database;
    debugPrint("💥 NUKING LOCAL DATA...");
    await db.delete('words');
    await db.delete('lessons');
    await db.delete('user_progress'); 
    debugPrint("🔄 Starting Fresh Sync...");
    await LocalDB.instance.syncEverything();
    debugPrint("✅ Done!");
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("App Repaired! Please restart the app completely.")),
      );
    }
  }

 Future<void> _signOut() async {
    try {
      // 🔥 STEP 1: Sign out of Google to clear the cached account
      // This ensures the "Choose Account" popup appears next time.
      await GoogleSignIn().signOut();

      // 🔥 STEP 2: Sign out of Supabase
      await Supabase.instance.client.auth.signOut();
      
      if (mounted) {
        // Remove all screens and go back to Login
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error signing out: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Profile", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: Navigator.canPop(context) 
            ? IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context))
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            
            // 1. AVATAR
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: const CircleAvatar(
                radius: 50,
                backgroundColor: AppColors.cardColor,
                child: Icon(Icons.person, size: 50, color: Colors.white),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // 2. USER EMAIL
            Text(
              _userEmail,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text(
              "Beginner Student",
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),

            const SizedBox(height: 40),

            // 3. MENU OPTIONS
            _buildProfileOption(Icons.settings, "Settings", () {}),
            _buildProfileOption(Icons.notifications, "Notifications", () {}),
            _buildProfileOption(Icons.language, "Language", () {}),

            const SizedBox(height: 20),

            // 🔥 4. NOTIFICATION CHECKER WIDGET 🔥
            FutureBuilder<bool>(
              future: NotificationService().areNotificationsEnabled(),
              builder: (context, snapshot) {
                // If waiting or enabled, show nothing
                if (!snapshot.hasData || snapshot.data == true) return const SizedBox.shrink();

                // If disabled, show the Red Warning Box
                return Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_off, color: Colors.redAccent),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Notifications are off! You might lose your streak.",
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await NotificationService().openSettings();
                          // Force rebuild to check status again after they come back
                          setState(() {});
                        },
                        child: const Text("ENABLE"),
                      )
                    ],
                  ),
                );
              },
            ),


            // 5. REPAIR BUTTON
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade900, 
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _fixMyApp, 
                icon: const Icon(Icons.build, color: Colors.white),
                label: const Text(
                  "REPAIR APP (Kill Duplicates)", 
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 6. LOGOUT BUTTON
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: _signOut,
                child: const Text(
                  "LOG OUT",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileOption(IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
        onTap: onTap,
      ),
    );
  }
}
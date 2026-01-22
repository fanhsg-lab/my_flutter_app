import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart'; // Import your theme
import '../local_db.dart'; // Import Local DB

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
    // 1. Get the DB
    final db = await LocalDB.instance.database;
    
    // 2. NUKE IT: Delete all local data tables
    debugPrint("💥 NUKING LOCAL DATA...");
    await db.delete('words');
    await db.delete('lessons');
    await db.delete('user_progress'); // We delete progress to remove 'ghosts'. 
                                      // Real progress will re-sync from Server.

    // 3. Force a fresh Sync immediately
    debugPrint("🔄 Starting Fresh Sync...");
    await LocalDB.instance.syncEverything();
    
    debugPrint("✅ Done! Restarting UI...");
    
    // 4. Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("App Repaired! Please restart the app completely.")),
      );
    }
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        // Remove all screens and go back to Login
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error signing out: $e")));
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
        // Back button only if pushed from another screen
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
            // Inside your "Fix" button or initState:
ElevatedButton(
  onPressed: () async {
     await LocalDB.instance.findHiddenWords();
     // Force refresh the dashboard after cleaning
     setState(() {}); 
  },
  child: const Text("Kill Duplicate Chapters"),
),
            const SizedBox(height: 40),

            // 4. LOGOUT BUTTON
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
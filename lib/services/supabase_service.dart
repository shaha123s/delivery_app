import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final client = Supabase.instance.client;

  // تسجيل مستخدم جديد
  static Future<void> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    await client.auth.signUp(
      email: email,
      password: password,
      data: {'name': name, 'role': role},
    );
    // حذفنا INSERT لأن الـ Trigger بيعملها تلقائياً
  }

  // تسجيل دخول
  static Future<String> signIn({
    required String email,
    required String password,
  }) async {
    await client.auth.signInWithPassword(email: email, password: password);

    final user = await client
        .from('users')
        .select('role')
        .eq('id', client.auth.currentUser!.id)
        .single();

    return user['role']; // 'client' أو 'driver'
  }
}

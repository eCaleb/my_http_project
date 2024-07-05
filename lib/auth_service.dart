import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<User?> register(String email, String password) async {
    try {
      print('Registering user: $email');
      final auth = FirebaseAuth.instance;
      final userCredential = await auth.createUserWithEmailAndPassword(email: email, password: password);
      print('User created: ${userCredential.user?.uid}');

      // Write user data to Firestore
      try {
        await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
          'email': email,
          'password': _hashPassword(password), // Hash the password before storing it
        });
        print('User data written to Firestore');
      } catch (e) {
        print('Error writing user data to Firestore: $e');
      }

      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      print('Error registering user: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      print('Error registering user: $e');
      return null;
    }
  }

Future<User?> login(String email, String password) async {
  try {
    print('Logging in user: $email');
    final auth = FirebaseAuth.instance;
    final userCredential = await auth.signInWithEmailAndPassword(email: email, password: password);
    print('User logged in: ${userCredential.user?.uid}');

    // Read user data from Firestore
    try {
      final userDataDoc = await _firestore.collection('users').doc(userCredential.user!.uid).get();
      final userData = userDataDoc.data() as Map<String, dynamic>?; // Cast to Map<String, dynamic>
      final storedHashedPassword = userData?['password']; // Now you can use the [] operator
      if (storedHashedPassword!= null) {
        final hashedPassword = _hashPassword(password);
        if (hashedPassword == storedHashedPassword) {
          print('Password matches!');
          return userCredential.user; // Return the User object here
        } else {
          print('Password does not match!');
          return null;
        }
      } else {
        print('No password found in Firestore!');
        return null;
      }
    } catch (e) {
      print('Error reading user data from Firestore: $e');
      return null;
    }
  } on FirebaseAuthException catch (e) {
    print('Error logging in user: ${e.code} - ${e.message}');
    return null;
  } catch (e) {
    print('Error logging in user: $e');
    return null;
  }
}

  Future<void> logout() async {
    await _auth.signOut();
  }

  User? getCurrentUser() {
    return _auth.currentUser;
  }
}
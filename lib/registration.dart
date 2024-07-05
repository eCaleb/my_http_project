import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  _RegistrationPageState createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureText = true;
  bool _obscureConfirmText = true;

  String? _emailErrorText;
  String? _passwordErrorText;
  String? _confirmPasswordErrorText;

  Future<void> _register(BuildContext context) async {
    final emailError = _validateEmail(_emailController.text);
    final passwordError = _validatePassword(_passwordController.text);
    final confirmPasswordError = _passwordController.text != _confirmPasswordController.text
        ? 'Passwords do not match'
        : null;

    if (emailError != null || passwordError != null || confirmPasswordError != null) {
      setState(() {
        _emailErrorText = emailError;
        _passwordErrorText = passwordError;
        _confirmPasswordErrorText = confirmPasswordError;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );

      User? user = userCredential.user;
      if (user != null) {
        await user.sendEmailVerification();

        // Hash the password
        final bytes = utf8.encode(_passwordController.text);
        final digest = sha256.convert(bytes);

        // Store user data in Firestore
        final firestore = FirebaseFirestore.instance;
        await firestore.collection('users').doc(user.uid).set({
          'email': _emailController.text,
          'password': digest.toString(), // Store the hashed password
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email sent. Please check your email.')),
        );

        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration failed: $e')),
      );
    }
  }

  String? _validateEmail(String email) {
    if (email.isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(email)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String password) {
    if (password.isEmpty) {
      return 'Password is required';
    }
    if (password.length < 6) {
      return 'Password must be at least 6 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must contain an uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Password must contain a lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must contain a number';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) {
      return 'Password must contain a special character';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 80,
                child: TextField(
                  controller: _emailController,
                  onChanged: (value) {
                    setState(() {
                      _emailErrorText = _validateEmail(value);
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'Email',
                    errorText: _emailErrorText,
                  ),
                ),
              ),
              SizedBox(
                height: 80,
                child: TextField(
                  controller: _passwordController,
                  onChanged: (value) {
                    setState(() {
                      _passwordErrorText = _validatePassword(value);
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'Password',
                    errorText: _passwordErrorText,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureText ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureText = !_obscureText;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureText,
                ),
              ),
              SizedBox(
                height: 80,
                child: TextField(
                  controller: _confirmPasswordController,
                  onChanged: (value) {
                    setState(() {
                      _confirmPasswordErrorText = _passwordController.text != value
                          ? 'Passwords do not match'
                          : null;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    errorText: _confirmPasswordErrorText,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmText ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmText = !_obscureConfirmText;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureConfirmText,
                ),
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: () => _register(context),
                      child: const Text('Register'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

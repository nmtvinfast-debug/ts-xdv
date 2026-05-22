import 'package:flutter/material.dart';
import '../models/auth_models.dart';

class AuthProvider extends ChangeNotifier {
  bool isAutoLoading = false;
  bool isLoggedIn = false;
  String? token;
  String? role;
  UserItem? user;

  void logout() {
    isLoggedIn = false;
    token = null;
    role = null;
    user = null;
    notifyListeners();
  }
}
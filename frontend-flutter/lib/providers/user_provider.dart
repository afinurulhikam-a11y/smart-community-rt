import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../models/user_model.dart';

class UserProvider extends ChangeNotifier {
  List<UserModel> _users = [];
  List<UserModel> _pendingUsers = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<UserModel> get users => _users;
  List<UserModel> get pendingUsers => _pendingUsers;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchUsers({
    String? role,
    String? search,
    bool? terdaftar,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final queryParams = <String, String>{};
      if (role != null && role.isNotEmpty) queryParams['role'] = role;
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (terdaftar == true) queryParams['terdaftar'] = 'true';

      final uri = Uri.parse(ApiConstants.users).replace(queryParameters: queryParams);
      final response = await ApiService.get(uri.toString());

      if (response['success'] == true && response['data'] != null) {
        final list = response['data'] as List<dynamic>;
        _users = list.map((json) => UserModel.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        _errorMessage = response['message']?.toString() ?? 'Gagal memuat data pengguna.';
      }
    } catch (e) {
      _errorMessage = 'Terjadi kesalahan jaringan: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchPendingUsers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await ApiService.get(ApiConstants.pendingUsers);
      if (response['success'] == true && response['data'] != null) {
        final list = response['data'] as List<dynamic>;
        _pendingUsers = list.map((json) => UserModel.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        _errorMessage = response['message']?.toString() ?? 'Gagal memuat pendaftaran pending.';
      }
    } catch (e) {
      _errorMessage = 'Terjadi kesalahan jaringan: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createUser({
    required String nama,
    required String email,
    required String password,
    String? role,
    String? noHp,
    String? noKk,
    String? alamat,
    String? noRt,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await ApiService.post(ApiConstants.users, body: {
        'nama': nama,
        'email': email,
        'password': password,
        if (role != null) 'role': role,
        if (noHp != null) 'no_hp': noHp,
        if (noKk != null) 'no_kk': noKk,
        if (alamat != null) 'alamat': alamat,
        if (noRt != null) 'no_rt': noRt,
      });

      if (response['success'] == true) {
        await fetchUsers();
        return true;
      } else {
        _errorMessage = response['message']?.toString() ?? 'Gagal membuat pengguna baru.';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Terjadi kesalahan: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateUserStatus(int id, bool isActive) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await ApiService.put(ApiConstants.userStatus(id.toString()), body: {
        'is_active': isActive,
      });

      if (response['success'] == true) {
        await fetchUsers();
        await fetchPendingUsers();
        return true;
      } else {
        _errorMessage = response['message']?.toString() ?? 'Gagal memperbarui status pengguna.';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Terjadi kesalahan: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateUserRole(int id, String role) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await ApiService.put(ApiConstants.userRole(id.toString()), body: {
        'role': role,
      });

      if (response['success'] == true) {
        await fetchUsers();
        return true;
      } else {
        _errorMessage = response['message']?.toString() ?? 'Gagal memperbarui peran pengguna.';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Terjadi kesalahan: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateUserCredentials({
    required String nik,
    String? noHp,
    String? role,
    String? password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final payload = <String, dynamic>{
        'nik': nik,
        if (noHp != null) 'no_hp': noHp,
        if (role != null) 'role': role,
        if (password != null && password.isNotEmpty) 'password': password,
      };

      final response = await ApiService.put(ApiConstants.userCredentials, body: payload);

      if (response['success'] == true) {
        await fetchUsers();
        return true;
      } else {
        _errorMessage = response['message']?.toString() ?? 'Gagal memperbarui kredensial.';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Terjadi kesalahan: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteUser(int id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await ApiService.delete(ApiConstants.user(id.toString()));

      if (response['success'] == true) {
        await fetchUsers();
        await fetchPendingUsers();
        return true;
      } else {
        _errorMessage = response['message']?.toString() ?? 'Gagal menghapus/menolak pengguna.';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Terjadi kesalahan: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

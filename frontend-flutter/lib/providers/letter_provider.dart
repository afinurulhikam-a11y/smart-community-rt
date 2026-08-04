import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../models/letter_model.dart';

class LetterProvider extends ChangeNotifier {
  List<LetterModel> _letters = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<LetterModel> get letters => _letters;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get pendingCount => _letters
      .where(
        (l) =>
            l.status.toLowerCase() == 'pending' ||
            l.status.toLowerCase() == 'diproses' ||
            l.status.toLowerCase() == 'diajukan',
      )
      .length;
  List<LetterModel> get pendingLetters => _letters
      .where(
        (l) =>
            l.status.toLowerCase() == 'pending' ||
            l.status.toLowerCase() == 'diproses' ||
            l.status.toLowerCase() == 'diajukan',
      )
      .toList();

  Future<void> fetchLetters({String? status}) async {
    _isLoading = true;
    notifyListeners();
    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;
    final response = await ApiService.get(
      ApiConstants.letters,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    if (response['success'] == true) {
      final dataList = response['data'] as List<dynamic>;
      _letters = dataList.map((j) => LetterModel.fromJson(j as Map<String, dynamic>)).toList();
      _errorMessage = null;
    } else {
      _errorMessage = response['message'] as String?;
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> createLetter({required String jenisSurat, required String keperluan}) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.post(
      ApiConstants.letters,
      body: {'jenis_surat': jenisSurat, 'keperluan': keperluan},
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchLetters();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateLetterStatus(String id, String status, {String? responseNote}) async {
    _isLoading = true;
    notifyListeners();
    final response = await ApiService.put(
      ApiConstants.approveLetter(id),
      body: {'status': status, if (responseNote != null) 'response_note': responseNote},
    );
    _isLoading = false;
    if (response['success'] == true) {
      await fetchLetters();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }
}

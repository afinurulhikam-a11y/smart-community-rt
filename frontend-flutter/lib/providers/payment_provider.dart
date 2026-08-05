import 'package:flutter/material.dart';

import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../models/payment_model.dart';

/// Pembayaran iuran lewat Midtrans.
///
/// Aplikasi TIDAK PERNAH menentukan sebuah tagihan lunas. Ia hanya memulai
/// pembayaran dan menanyakan statusnya; backend yang mengonfirmasi ke server
/// Midtrans, lalu memutuskan.
class PaymentProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  List<PaymentRiwayat> _riwayat = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<PaymentRiwayat> get riwayat => _riwayat;

  /// Memulai pembayaran untuk beberapa tagihan sekaligus.
  Future<PaymentSession?> mulai(List<String> billIds) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final r = await ApiService.post(ApiConstants.payMulai, body: {'bill_ids': billIds});

    _isLoading = false;
    if (r['success'] == true && r['data'] != null) {
      notifyListeners();
      return PaymentSession.fromJson(r['data'] as Map<String, dynamic>);
    }

    _errorMessage = r['message']?.toString() ?? 'Gagal memulai pembayaran.';
    notifyListeners();
    return null;
  }

  /// Menanyakan status ke backend, yang meneruskannya ke Midtrans.
  ///
  /// Dipakai tombol "Periksa Status" dan tetap sahih walaupun webhook belum
  /// bisa menjangkau backend — misalnya saat server masih di jaringan lokal.
  Future<PaymentStatus?> periksa(String orderId) async {
    _isLoading = true;
    notifyListeners();

    final r = await ApiService.get(ApiConstants.payStatus(orderId));

    _isLoading = false;
    if (r['success'] == true && r['data'] != null) {
      notifyListeners();
      return PaymentStatus.fromJson(r['data'] as Map<String, dynamic>);
    }

    _errorMessage = r['message']?.toString() ?? 'Gagal memeriksa status.';
    notifyListeners();
    return null;
  }

  /// Melepas pembayaran yang ditinggalkan, agar tagihannya bisa dibayar ulang
  /// tanpa menunggu kedaluwarsa dari Midtrans.
  Future<bool> batalkan(String orderId) async {
    final r = await ApiService.post(ApiConstants.payBatal(orderId));
    if (r['success'] == true) return true;
    _errorMessage = r['message']?.toString();
    notifyListeners();
    return false;
  }

  Future<void> muatRiwayat() async {
    _isLoading = true;
    notifyListeners();

    final r = await ApiService.get(ApiConstants.payRiwayat);
    if (r['success'] == true) {
      _riwayat = (r['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(PaymentRiwayat.fromJson)
          .toList();
      _errorMessage = null;
    } else {
      _errorMessage = r['message']?.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Simulasikan pembayaran lunas untuk keperluan Sandbox / Testing Mode.
  Future<bool> simulasiLunas(String orderId) async {
    _isLoading = true;
    notifyListeners();

    final r = await ApiService.post(ApiConstants.paySimulasiLunas(orderId));

    _isLoading = false;
    if (r['success'] == true) {
      notifyListeners();
      return true;
    }

    _errorMessage = r['message']?.toString() ?? 'Gagal melakukan simulasi pembayaran.';
    notifyListeners();
    return false;
  }
}

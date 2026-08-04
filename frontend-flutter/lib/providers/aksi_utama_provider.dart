import 'package:flutter/material.dart';

/// Aksi utama layar yang sedang terbuka, untuk ditampilkan sebagai
/// FloatingActionButton oleh kerangka aplikasi.
///
/// Tombol "Tambah" tiap layar semula berada di bilah judulnya sendiri, tercampur
/// dengan tombol Excel dan PDF. Di ponsel semuanya berdesakan dan aksi yang
/// paling sering dipakai tidak lebih menonjol daripada yang jarang. FAB adalah
/// jawaban baku Android untuk itu: satu tombol, selalu di sudut yang sama,
/// terjangkau ibu jari.
///
/// Layar tidak bisa memasang FAB sendiri karena bukan `Scaffold` — semuanya
/// dirender di dalam satu Scaffold milik MainDashboard. Kelas ini yang
/// menjembatani: layar mendaftarkan aksinya, kerangka yang menggambar
/// tombolnya.
class AksiUtamaProvider extends ChangeNotifier {
  VoidCallback? _aksi;
  String? _label;
  IconData? _ikon;

  VoidCallback? get aksi => _aksi;
  String? get label => _label;
  IconData? get ikon => _ikon;
  bool get ada => _aksi != null;

  /// Dipanggil layar saat terbuka.
  ///
  /// Aman dipanggil berulang kali dari `build`: bila isinya sama persis, tidak
  /// ada pemberitahuan yang dikirim, sehingga tidak terjadi rebuild tanpa akhir.
  void pasang({required VoidCallback aksi, required String label, required IconData ikon}) {
    if (_label == label && _ikon == ikon && _aksi != null) {
      // Callback-nya diperbarui diam-diam — closure baru dibuat setiap build
      // dan pasti berbeda, tetapi maksudnya sama.
      _aksi = aksi;
      return;
    }
    _aksi = aksi;
    _label = label;
    _ikon = ikon;
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  /// Dipanggil layar yang tidak punya aksi utama, supaya FAB milik layar
  /// sebelumnya tidak tertinggal di layar ini.
  void lepas() {
    if (_aksi == null && _label == null) return;
    _aksi = null;
    _label = null;
    _ikon = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }
}

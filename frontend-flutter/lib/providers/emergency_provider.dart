import 'package:flutter/material.dart';
import '../core/constants/api_constants.dart';
import '../core/services/api_service.dart';
import '../core/services/websocket_service.dart';
import '../models/emergency_model.dart';

class EmergencyProvider extends ChangeNotifier {
  List<EmergencyModel> _alerts = [];
  bool _isLoading = false;
  bool _isSending = false;
  String? _errorMessage;
  String? _successMessage;

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalData = 0;
  int _perPage = 10;

  EmergencyProvider() {
    fetchAlerts();
  }

  List<EmergencyModel> get alerts => _alerts;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalData => _totalData;
  int get perPage => _perPage;

  EmergencyModel? get activeAlert {
    try {
      return _alerts.firstWhere((a) => a.isActive);
    } catch (_) {
      return null;
    }
  }

  /// Apakah ada kejadian darurat yang sedang AKTIF menurut backend.
  ///
  /// Sumbernya `/emergency/alarm/status`, bukan ingatan aplikasi ini. Keadaan
  /// yang hanya hidup di memori akan salah begitu aplikasi dibuka ulang, atau
  /// begitu orang lain menyalakan alarm dari perangkat lain — dan pada tombol
  /// darurat, layar yang menampilkan keadaan salah lebih berbahaya daripada
  /// layar yang mengaku tidak tahu.
  bool _alarmMenyala = false;
  bool get alarmMenyala => _alarmMenyala;

  /// Kejadian aktif beserta izin yang DIHITUNG SERVER. Null bila tidak ada.
  ///
  /// Memuat `emergency_id`, `nama_pengaktif`, `milik_saya`, dan
  /// `boleh_matikan`. Yang terakhir dipakai layar untuk memilih tombol —
  /// tetapi ia kenyamanan, bukan pengaman: endpoint OFF menolak sendiri bila
  /// klien mengabaikannya.
  Map<String, dynamic>? _kejadianAktif;
  Map<String, dynamic>? get kejadianAktif => _kejadianAktif;

  /// True bila pengguna ini boleh mematikan kejadian yang sedang aktif.
  bool get bolehMatikan => _kejadianAktif?['boleh_matikan'] == true;

  /// True bila kejadian aktif dinyalakan oleh orang lain.
  bool get daruratMilikOrangLain =>
      _kejadianAktif != null && _kejadianAktif!['milik_saya'] != true;

  String get namaPengaktif =>
      (_kejadianAktif?['nama_pengaktif'] as String?) ?? 'Tidak diketahui';

  /// Batas panjang keterangan kejadian. **Cermin dari `emergency.controller.js`**
  /// (`KETERANGAN_MIN` / `KETERANGAN_MAKS`).
  ///
  /// Nilai di sini hanya untuk memberi tahu pemakai lebih awal — bukan
  /// pengaman. Backend memvalidasi ulang setiap permintaan, jadi klien yang
  /// dimodifikasi tetap ditolak. Bila batas di backend berubah, ubah di sini.
  static const int keteranganMin = 5;
  static const int keteranganMaks = 500;

  /// Keterangan kejadian yang sedang aktif, apa adanya dari backend.
  ///
  /// Kosong bila tidak ada kejadian aktif — layar memakai kekosongan itu untuk
  /// memilih antara menampilkan detail atau tidak menampilkan blok itu sama
  /// sekali, bukan menampilkan blok kosong yang membingungkan.
  String get keteranganKejadian =>
      (_kejadianAktif?['message'] as String?)?.trim() ?? '';

  /// Keterangan siap tampil — penanda legacy sudah diterjemahkan menjadi
  /// kalimat yang bisa dibaca. Lihat [keteranganUntukTampilan].
  String get keteranganKejadianTampil =>
      keteranganKejadian.isEmpty ? '' : keteranganUntukTampilan(keteranganKejadian);

  /// True bila kejadian aktif dinyalakan klien lama tanpa keterangan.
  bool get kejadianTanpaKeteranganLegacy =>
      keteranganKejadian == penandaLegacyKeterangan;

  /// Kapan kejadian aktif dinyalakan. Null bila tidak ada kejadian aktif.
  DateTime? get waktuKejadian {
    final v = _kejadianAktif?['created_at'];
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  /// Filter status terakhir yang dipakai daftar riwayat.
  ///
  /// Disimpan supaya penyegaran setelah mutasi memuat ulang daftar yang SAMA
  /// dengan yang sedang dilihat. Tanpa ini, menekan Selesaikan sambil memfilter
  /// "Aktif" akan memuat ulang daftar tanpa filter, dan layar tiba-tiba
  /// menampilkan kejadian lain — terlihat seperti aksinya salah sasaran.
  String? _filterStatus;

  /// Menyegarkan SELURUH keadaan darurat: status sirene dan daftar riwayat.
  ///
  /// ===================================================================
  /// Kenapa keduanya, selalu, dari satu tempat
  /// ===================================================================
  ///
  /// Dua layar membaca dua bagian keadaan yang berbeda dari provider yang sama:
  /// kartu dasbor membaca `alarm_aktif`/`kejadian_aktif`, sedangkan Status
  /// Darurat membaca `alerts`. Sebelumnya tiap mutasi hanya menyegarkan
  /// separuhnya:
  ///
  ///   kendaliAlarm  → hanya status   → riwayat basi
  ///   dismissAlarm  → hanya riwayat  → kartu dasbor MASIH "AKTIF"
  ///   triggerAlarm  → hanya riwayat  → kartu dasbor tidak tahu ada darurat
  ///
  /// Akibatnya menyelesaikan darurat dari Status Darurat meninggalkan dasbor
  /// menyala merah untuk kejadian yang sudah ditutup — keadaan yang salah pada
  /// layar yang justru paling tidak boleh salah.
  ///
  /// Menyatukannya di satu metode berarti mutasi baru tidak bisa lupa
  /// menyegarkan separuh yang lain: yang perlu diingat hanya memanggil ini.
  Future<void> segarkanDarurat() async {
    await Future.wait([
      muatStatusAlarm(),
      fetchAlerts(status: _filterStatus, page: _currentPage, limit: _perPage),
    ]);
  }

  // ===================================================================
  // Sinkronisasi lintas PERANGKAT lewat WebSocket yang sudah ada
  // ===================================================================
  //
  // Penyegaran setelah mutasi hanya menolong perangkat yang MENEKAN tombolnya.
  // Kalau darurat ditutup dari ponsel lain, layar di sini baru menyusul saat
  // aplikasi di-resume — bisa belasan menit kemudian.
  //
  // `WebSocketService` sudah menerima `ALARM_ON`/`ALARM_OFF` dan sudah
  // menguraikannya menjadi `lastAlarm`. Yang kurang hanyalah seseorang yang
  // mendengarkan dan membaca ulang keadaan. Jadi tidak ada koneksi baru, tidak
  // ada protokol baru, dan tidak ada sumber keadaan kedua — provider ini tetap
  // satu-satunya yang menyimpan status darurat.

  WebSocketService? _ws;

  /// Tanda kejadian darurat terakhir yang sudah ditindaklanjuti.
  ///
  /// `WebSocketService` memanggil `notifyListeners()` untuk SETIAP pesan yang
  /// masuk — termasuk pesan yang sama sekali bukan tentang darurat, dan
  /// termasuk saat tersambung atau terputus. Tanpa tanda ini, satu siaran
  /// beruntun akan memicu berkali-kali `segarkanDarurat()`, dan tiap penyegaran
  /// berarti dua permintaan HTTP.
  String? _tandaDarurat;
  bool _wsTersambungTerakhir = false;

  /// Menyambungkan provider ini ke siaran realtime.
  ///
  /// Aman dipanggil berkali-kali: pemanggilan dengan layanan yang SAMA tidak
  /// mendaftarkan pendengar kedua. Itu penting karena pemanggilnya berada di
  /// `initState` yang bisa berjalan lagi setelah hot reload.
  void pasangSumberRealtime(WebSocketService ws) {
    if (identical(_ws, ws)) return;

    _ws?.removeListener(_padaPerubahanWs);
    _ws = ws;

    // Keadaan awal dicatat TANPA menyegarkan: kartu dasbor sudah memuat
    // statusnya sendiri saat dipasang, jadi menyegarkan lagi di sini hanya
    // menambah permintaan yang tidak mengubah apa pun.
    _tandaDarurat = _tandaDari(ws);
    _wsTersambungTerakhir = ws.isConnected;

    ws.addListener(_padaPerubahanWs);
  }

  /// Melepas pendengar. Wajib dipanggil saat pemiliknya dibuang, kalau tidak
  /// pendengarnya tetap hidup dan provider ini ikut tertahan di memori.
  void lepasSumberRealtime() {
    _ws?.removeListener(_padaPerubahanWs);
    _ws = null;
  }

  /// Tanda diambil dari PESAN TERAKHIR yang benar-benar tiba, bukan dari
  /// `lastAlarm`.
  ///
  /// Bedanya menentukan, dan uji menemukannya: `lastAlarm` menjadi null pada
  /// `ALARM_OFF` maupun ketika memang belum pernah ada apa-apa. Jadi kalau
  /// perangkat ini tidak sempat menerima `ALARM_ON` — misalnya daruratnya
  /// dinyalakan lewat tombol dasbor, yang backend-nya memang tidak menyiarkan —
  /// maka `ALARM_OFF` yang menyusul terbaca "tidak ada perubahan", dan layar
  /// tetap menyala merah untuk kejadian yang sudah ditutup.
  ///
  /// Dengan menandai pesannya sendiri (`tipe:alert_id`), sebuah `ALARM_OFF`
  /// tetap dikenali sebagai peristiwa baru walau keadaan turunannya sama.
  String _tandaDari(WebSocketService ws) {
    for (final m in ws.messages) {
      final t = m['type'];
      if (t == 'ALARM_ON' || t == 'ALARM_OFF') {
        return '$t:${m['alert_id']}';
      }
    }
    return 'KOSONG';
  }

  void _padaPerubahanWs() {
    final ws = _ws;
    if (ws == null) return;

    final tanda = _tandaDari(ws);

    // Tersambung KEMBALI setelah putus juga memicu pembacaan ulang: selama
    // terputus, siaran apa pun hilang tanpa jejak, jadi keadaan di layar tidak
    // bisa dipercaya lagi. Terputusnya sendiri tidak memicu apa-apa — tidak
    // ada gunanya menembakkan permintaan saat jaringan memang sedang mati.
    final tersambungLagi = ws.isConnected && !_wsTersambungTerakhir;
    _wsTersambungTerakhir = ws.isConnected;

    if (tanda == _tandaDarurat && !tersambungLagi) return;
    _tandaDarurat = tanda;

    segarkanDarurat();
  }

  /// Menyegarkan keadaan sirene dari backend.
  ///
  /// Gagal diam-diam pada kegagalan jaringan: kartu tetap menampilkan keadaan
  /// terakhir yang diketahui, dan tidak berpura-pura alarm sudah mati hanya
  /// karena server sedang tidak terjangkau.
  Future<void> muatStatusAlarm() async {
    final r = await ApiService.get(ApiConstants.emergencyAlarmStatus);
    if (r['success'] != true) return;

    final d = r['data'] as Map<String, dynamic>?;
    if (d == null) return;

    _alarmMenyala = d['alarm_aktif'] == true;
    _kejadianAktif = d['kejadian_aktif'] as Map<String, dynamic>?;
    notifyListeners();
  }

  /// True selama satu perintah alarm sedang dikirim. Dipakai layar untuk
  /// mengunci tombol, sehingga tekan-berkali-kali tidak menjadi banyak
  /// permintaan.
  bool _mengirimAlarm = false;
  bool get mengirimAlarm => _mengirimAlarm;

  /// Menyalakan atau mematikan alat lewat backend.
  ///
  /// [aksi] hanya boleh 'ON' atau 'OFF'. PIN diverifikasi DI BACKEND; nilai di
  /// sini hanya diteruskan. Aplikasi tidak pernah menyentuh broker MQTT dan
  /// tidak pernah memegang kredensialnya.
  ///
  /// Menyusun badan permintaan `POST /emergency/alarm`.
  ///
  /// Dipisah menjadi fungsi tersendiri supaya bisa diuji tanpa jaringan —
  /// isinya adalah bagian yang paling mudah salah diam-diam, dan kesalahannya
  /// tidak memunculkan galat apa pun.
  ///
  /// ===================================================================
  /// Kenapa `keterangan` DAN `message` dikirim berdua
  /// ===================================================================
  ///
  /// Klien dan backend tidak naik pada detik yang sama. Backend produksi hari
  /// ini belum mengenal `keterangan` sama sekali — ia membaca
  /// `req.body?.message`, dan bila kosong memakai kalimat bawaannya sendiri.
  /// Jadi mengirim `keterangan` SAJA berarti kalimat yang diketik warga
  /// dibuang diam-diam, lalu Riwayat Darurat menampilkan "Alarm darurat
  /// dinyalakan dari dasbor" seolah-olah itu yang ia tulis. Kolomnya terisi,
  /// tetapi isinya bukan miliknya — dan tidak ada satu pun galat yang muncul.
  ///
  /// Dengan keduanya dikirim bernilai sama, satu badan permintaan benar di
  /// kedua sisi: backend lama membaca `message`, backend baru membaca
  /// `keterangan` lebih dulu (`req.body?.keterangan ?? req.body?.message`).
  /// Karena nilainya identik, tidak ada tafsir yang bisa berbeda di antara
  /// keduanya.
  ///
  /// `message` boleh dilepas setelah backend berketerangan terpasang di
  /// produksi.
  @visibleForTesting
  static Map<String, dynamic> susunBadanAlarm(String aksi, String pin, String? keterangan) {
    final body = <String, dynamic>{'aksi': aksi, 'pin': pin};

    // Hanya untuk ON, dan hanya bila ada isinya. Menyertakan field kosong pada
    // OFF membuat badan permintaan mengaku membawa sesuatu yang tidak dipakai.
    final k = keterangan?.trim() ?? '';
    if (aksi == 'ON' && k.isNotEmpty) {
      body['keterangan'] = k;
      body['message'] = k;
    }

    return body;
  }

  /// [keterangan] WAJIB untuk aksi `ON` dan diabaikan untuk `OFF`. Backend
  /// menolak `ON` tanpa keterangan yang sah dengan 400, jadi mengirimkannya
  /// bukan pilihan.
  ///
  /// Mengembalikan pesan galat bila gagal, atau null bila berhasil — pemanggil
  /// butuh teksnya untuk ditampilkan, bukan sekadar true/false.
  Future<String?> kendaliAlarm(String aksi, String pin, {String? keterangan}) async {
    if (_mengirimAlarm) return 'Perintah sebelumnya masih diproses.';

    _mengirimAlarm = true;
    _errorMessage = null;
    notifyListeners();

    final r = await ApiService.post(
      ApiConstants.emergencyAlarm,
      body: susunBadanAlarm(aksi, pin, keterangan),
    );

    _mengirimAlarm = false;

    if (r['success'] == true) {
      _successMessage = r['message'] as String?;
      notifyListeners();
      // Keadaan diambil ULANG dari backend, bukan disimpulkan dari aksi yang
      // baru dikirim. Menyimpulkannya membuat layar yakin alarm menyala walau
      // kejadiannya ternyata sudah ditutup orang lain sedetik sebelumnya.
      //
      // Riwayat ikut disegarkan supaya Status Darurat langsung menampilkan
      // kejadian yang sama sebagai SELESAI tanpa perlu dibuka ulang.
      await segarkanDarurat();
      return null;
    }

    // Server tidak terjangkau dibedakan dari server yang menolak. Pada tombol
    // darurat perbedaan itu menentukan tindakan berikutnya: yang satu berarti
    // coba lagi, yang lain berarti periksa alatnya langsung.
    final galat = r[ApiService.penandaOffline] == true
        ? 'Tidak dapat menghubungi server. Alarm BELUM tentu menyala — periksa alat secara langsung.'
        : (r['message'] as String? ?? 'Gagal mengirim perintah alarm.');
    _errorMessage = galat;
    notifyListeners();
    return galat;
  }

  Future<bool> triggerAlarm({String? message, String? pin}) async {
    _isSending = true;
    _errorMessage = null;
    notifyListeners();
    final body = <String, dynamic>{};
    if (message != null) body['message'] = message;
    if (pin != null) body['pin'] = pin;

    final response = await ApiService.post(
      ApiConstants.emergencyTrigger,
      body: body,
    );
    _isSending = false;
    if (response['success'] == true) {
      _successMessage = response['message'] as String?;
      // Status ikut disegarkan: memicu darurat membuat kejadian aktif, dan
      // kartu dasbor harus langsung menyala tanpa menunggu dibuka ulang.
      await segarkanDarurat();
      notifyListeners();
      return true;
    } else {
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<bool> dismissAlarm(String alertId, {String? pin}) async {
    _isLoading = true;
    _errorMessage = null;

    final body = <String, dynamic>{};
    if (pin != null) body['pin'] = pin;

    final response = await ApiService.post(
      ApiConstants.emergencyDismiss(alertId),
      body: body,
    );
    _isLoading = false;
    if (response['success'] == true) {
      _successMessage = response['message'] as String?;
      // Inilah perbaikan bug lintas layar: sebelumnya hanya riwayat yang
      // disegarkan, sehingga menekan Selesaikan di Status Darurat menutup
      // kejadiannya di backend tetapi meninggalkan kartu dasbor tetap "AKTIF".
      await segarkanDarurat();
      notifyListeners();
      return true;
    } else {
      // GAGAL — tidak ada keadaan lokal yang diubah. 403, 409, atau jaringan
      // putus tidak boleh membuat layar mengaku kejadiannya sudah selesai;
      // yang menentukan tetap backend.
      _errorMessage = response['message'] as String?;
      notifyListeners();
      return false;
    }
  }

  Future<void> fetchAlerts({String? status, int page = 1, int limit = 10, bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }
    _currentPage = page;
    _perPage = limit;
    // Diingat supaya `segarkanDarurat()` memuat ulang daftar yang sama.
    _filterStatus = status;

    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (status != null) queryParams['status'] = status;

    final response = await ApiService.get(
      ApiConstants.emergencyAlerts,
      queryParams: queryParams,
    );
    if (response['success'] == true) {
      final dataList = response['data'] as List<dynamic>;
      _alerts = dataList.map((j) => EmergencyModel.fromJson(j as Map<String, dynamic>)).toList();
      _errorMessage = null;

      if (response['pagination'] != null) {
        final p = response['pagination'] as Map<String, dynamic>;
        _totalData = p['total_data'] as int? ?? _alerts.length;
        _totalPages = p['total_pages'] as int? ?? 1;
        _currentPage = p['current_page'] as int? ?? page;
        _perPage = p['per_page'] as int? ?? limit;
      } else {
        _totalData = _alerts.length;
        _totalPages = 1;
      }
    } else {
      _errorMessage = response['message'] as String?;
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Kosongkan seluruh state saat pengguna keluar.
  ///
  /// Provider di aplikasi ini dibuat sekali di MultiProvider akar dan hidup
  /// selama proses berjalan. Tanpa ini, data pengguna sebelumnya masih ada
  /// di memori saat orang lain masuk — dan sempat terlihat di layar sampai
  /// pengambilan data yang baru selesai. Pada perangkat bersama yang dipakai
  /// pengurus bergantian, itu kebocoran yang nyata, bukan sekadar kosmetik.
  @override
  void dispose() {
    // Pendengar dilepas lebih dulu. `WebSocketService` hidup selama proses
    // berjalan, jadi pendengar yang tertinggal akan menahan provider ini di
    // memori dan tetap memanggil `segarkanDarurat()` sesudah ia dibuang.
    lepasSumberRealtime();
    super.dispose();
  }

  void bersihkan() {
    _alerts = [];
    _isLoading = false;
    _isSending = false;
    _errorMessage = null;
    _successMessage = null;
    _currentPage = 1;
    _totalPages = 1;
    _totalData = 0;
    _perPage = 10;

    // Keadaan sirene ikut dikosongkan: pengguna berikutnya di perangkat
    // bersama tidak boleh mewarisi kejadian milik pengguna sebelumnya, apalagi
    // nama pelapornya.
    _alarmMenyala = false;
    _kejadianAktif = null;
    _filterStatus = null;

    // Tanda direset supaya siaran pertama setelah login berikutnya tetap
    // dianggap perubahan dan memicu pembacaan ulang.
    _tandaDarurat = null;

    notifyListeners();
  }
}

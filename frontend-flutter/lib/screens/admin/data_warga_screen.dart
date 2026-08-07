import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/responsif.dart';
import 'dart:convert';
import '../../providers/warga_provider.dart';
import '../../providers/permission_provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/api_service.dart';
import '../../core/constants/api_constants.dart';
import '../../../widgets/banner_lihat_saja.dart';
import '../../../widgets/tabel_responsif.dart';
import '../../../widgets/tombol_kembali.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';
import '../../core/izin_layar.dart';

/// Kata sandi bawaan untuk setiap akun warga baru — cermin dari nilai tetap
/// di backend (warga.controller.js). Warga wajib menggantinya di login
/// pertama (must_change_password = true), jadi nilai ini hanya jembatan
/// masuk sekali pakai.
const String _kataSandiBawaan = '12345678';

/// Pilihan baku untuk field demografi.
///
/// Sengaja dropdown, bukan teks bebas: layar Statistik mengelompokkan data
/// dengan GROUP BY pada nilai mentah kolom ini, jadi variasi ejaan akan
/// memecah satu kategori menjadi beberapa irisan chart.
const List<String> _opsiStatusPerkawinan = [
  'Belum Menikah',
  'Menikah',
  'Cerai Hidup',
  'Cerai Mati',
];

const List<String> _opsiAgama = [
  'Islam',
  'Kristen',
  'Katolik',
  'Hindu',
  'Buddha',
  'Konghucu',
  'Lainnya',
];

const List<String> _opsiPendidikan = [
  'Tidak Sekolah',
  'SD',
  'SMP',
  'SMA/SMK',
  'D3',
  'S1',
  'S2',
  'S3',
];

const List<String> _opsiPekerjaan = [
  'PNS',
  'TNI/Polri',
  'Karyawan Swasta',
  'Wiraswasta',
  'Petani',
  'Buruh',
  'Ibu Rumah Tangga',
  'Pelajar/Mahasiswa',
  'Pensiunan',
  'Pekerja Lepas',
  'Belum/Tidak Bekerja',
];

const List<String> _opsiStatusRumah = ['Milik Sendiri', 'Sewa', 'Kontrak', 'Kos', 'Menumpang'];

class DataWargaScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const DataWargaScreen({super.key, this.onBack});

  @override
  State<DataWargaScreen> createState() => _DataWargaScreenState();
}

/// Kode modul di tabel izin. Bendahara hanya punya `view` di sini.
const String _kodeIzin = 'kependudukan.warga';

class _DataWargaScreenState extends State<DataWargaScreen> {
  bool get _bolehTambah => context.watch<PermissionProvider>().bolehTambah(_kodeIzin);
  bool get _bolehUbah => context.watch<PermissionProvider>().bolehUbah(_kodeIzin);
  bool get _bolehHapus => context.watch<PermissionProvider>().bolehHapus(_kodeIzin);

  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WargaProvider>().fetchWarga();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WargaProvider>();
    final paginatedData = provider.wargaList;

    // TIDAK ada `if (isLoading) return spinner` di sini lagi.
    //
    // Cabang itu membuang SELURUH layar — header, filter, tabel, dan kotak
    // pencariannya sendiri. Melepas kotak pencarian dari pohon widget ikut
    // membuang FocusNode-nya, sehingga papan ketik tertutup dan kursornya
    // hilang setiap kali data dimuat. Pengguna harus menyentuh kotaknya lagi
    // untuk melanjutkan mengetik.
    //
    // Sekarang kerangkanya tetap terpasang dan hanya bagian tabel yang
    // digantikan indikator — lihat `_buildIsiTabel` di bawah.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BannerLihatSaja(kode: _kodeIzin),
        // Top Header and Action Buttons
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              // Breadcrumb internal di layar lebar — nama menu utama sudah ditampilkan di header atas.
              if (!pakaiKartu(context))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TombolKembali(onPressed: widget.onBack),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B7A6A).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.people, color: Color(0xFF1B7A6A), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Kependudukan / Data Warga',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _isDarkMode ? Colors.white70 : context.teksKedua,
                        ),
                      ),
                    ),
                  ],
                ),
              Wrap(
                spacing: AppTheme.spasiS,
                runSpacing: AppTheme.spasiS,
                children: [
                  // Export tetap terbuka untuk role lihat-saja — menyalin data
                  // yang boleh dibaca bukan perubahan. Tambah dan Import jelas
                  // menulis, jadi keduanya menuntut izin `create`.
                  if (_bolehTambah)
                    _buildActionButton(
                      Icons.person_add,
                      'Tambah Warga',
                      const Color(0xFF1B7A6A),
                      onTap: () => _showAddWargaDialog(context),
                    ),
                  if (_bolehTambah)
                    _buildActionButton(
                      Icons.upload_file,
                      'Import Excel',
                      const Color(0xFF0284C7),
                      onTap: () => _importDataWarga(context),
                    ),
                  _buildActionButton(
                    Icons.description,
                    'Export Excel',
                    const Color(0xFF059669),
                    onTap: () {
                      context.read<WargaProvider>().downloadExcel();
                    },
                  ),
                  _buildActionButton(
                    Icons.picture_as_pdf,
                    'Export PDF',
                    const Color(0xFFDC2626),
                    onTap: () {
                      context.read<WargaProvider>().downloadPdf();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // SECTION 4: DATA TABLE
        Container(
          padding: EdgeInsets.all(paddingKartu(context)),
          decoration: BoxDecoration(
            color: context.latarKartu,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.garis),
          ),
          child: Column(
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  Wrap(
                    children: [
                      const Icon(Icons.list_alt, color: Color(0xFF1B7A6A)),
                      const SizedBox(width: 8),
                      Text(
                        'Detail Data Warga',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: context.teksUtama,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${provider.totalData} Orang',
                          style: const TextStyle(
                            color: Color(0xFF065F46),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Pencarian',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.teksKedua,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // `Flexible` + `ConstrainedBox`, BUKAN `SizedBox(width:
                    // lebarKolomFilter(...))`.
                    //
                    // `lebarKolomFilter` mengembalikan `double.infinity` pada
                    // layar sempit supaya kotak filter memenuhi satu baris —
                    // itu benar di dalam `Wrap` atau `Column`, tetapi di dalam
                    // `Row` lebar tak hingga melanggar batasan tata letak dan
                    // melempar "BoxConstraints forces an infinite width".
                    //
                    // Bentuk ini menjaga kedua perilakunya: melebar mengikuti
                    // ruang yang ada, dengan batas 280 di layar lebar.
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(color: context.teksUtama, fontSize: 13),
                          // Mencari saat ENTER, bukan setiap huruf.
                          //
                          // Dulu `onChanged` menembakkan satu permintaan per
                          // ketukan tombol: mengetik "Budi" berarti empat
                          // panggilan ke server. `ApiService` mencoba ulang dua
                          // kali saat gagal, jadi di jaringan buruk angkanya
                          // berlipat — dan tanpa penomoran permintaan, jawaban
                          // untuk "B" yang datang belakangan bisa menimpa hasil
                          // "Budi" sehingga daftarnya tidak lagi cocok dengan
                          // isi kotaknya.
                          //
                          // Kas RT, Log Aktivitas, Peminjaman, dan E-Visitor
                          // sudah memakai pola ini; layar inilah yang berbeda
                          // sendiri.
                          textInputAction: TextInputAction.search,
                          onSubmitted: (val) {
                            _searchQuery = val.trim();
                            context.read<WargaProvider>().fetchWarga(
                              search: _searchQuery.isEmpty ? null : _searchQuery,
                              page: 1,
                            );
                          },
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: context.latarKartu,
                            hintStyle: TextStyle(color: context.teksTersier, fontSize: 13),
                            hintText: 'Cari nama, NIK, KK — tekan Enter',
                            // Ikonnya dibuat bisa ditekan, bukan sekadar hiasan:
                            // di ponsel tombol Enter tidak selalu terlihat, dan
                            // pencarian yang hanya bisa dijalankan lewat tombol
                            // tak kasatmata sama saja dengan tidak ada.
                            prefixIcon: IconButton(
                              icon: const Icon(Icons.search, size: 18),
                              color: context.teksUtama,
                              tooltip: 'Cari',
                              onPressed: () {
                                _searchQuery = _searchController.text.trim();
                                context.read<WargaProvider>().fetchWarga(
                                  search: _searchQuery.isEmpty ? null : _searchQuery,
                                  page: 1,
                                );
                              },
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: context.garis,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: context.garis,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF1B7A6A)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: context.latarKartu,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.garis),
                ),
                child: Column(
                  children: [
                    // Tinggi dipatok HANYA di layar lebar, tempat isinya
                    // memang tabel: sepuluh baris × ~50px pas di 560.
                    //
                    // Di ponsel isinya kartu bertumpuk, ~250px per warga.
                    // Tiga warga saja sudah ~1.046px, sehingga batas 560 itu
                    // memotongnya dan meluber 486px tepat menimpa paginasi.
                    // Halamannya sendiri sudah bisa digulir, jadi di sini
                    // daftarnya dibiarkan setinggi isinya.
                    Container(
                      constraints: pakaiKartu(context)
                          ? const BoxConstraints()
                          : const BoxConstraints(minHeight: 560),
                      // Indikator memuat dibatasi HANYA di area tabel.
                      // Kerangka di atasnya — termasuk kotak pencarian —
                      // tidak pernah dilepas, jadi fokus dan papan ketik
                      // bertahan selama data diambil.
                      child: provider.isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(40),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : _buildWargaTable(provider, paginatedData),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    final tombol = ElevatedButton.icon(
      onPressed: onTap ?? () {},
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spasiL),
        shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadiusS),
      ),
    );

    if (!pakaiKartu(context)) return tombol;

    // Di ponsel keempat tombol turun menjadi dua baris. Dengan lebar mengikuti
    // panjang label, "Tambah Warga" dan "Import Excel" jadi tidak sama besar
    // dan barisnya terlihat timpang. Setengah lebar layar membuat keduanya
    // rata, dan baris kedua sejajar dengan baris pertama.
    final lebarLayar = MediaQuery.of(context).size.width;
    final lebarTombol = (lebarLayar - paddingKonten(context) * 2 - AppTheme.spasiS) / 2;
    return SizedBox(width: lebarTombol, child: tombol);
  }

  Widget _buildWargaTable(WargaProvider provider, List<Map<String, dynamic>> paginatedData) {
    return Padding(
      padding: EdgeInsets.all(pakaiKartu(context) ? 12 : 0),
      child: TabelResponsif(
        tinggiBarisMin: 50,
        tinggiBarisMaks: 50,
        kolom: const [
          'NO',
          'NIK',
          'NAMA LENGKAP',
          'NO KK',
          'STATUS HUBUNGAN',
          'TGL LAHIR',
          'PERKAWINAN',
          'AGAMA',
          'DOMISILI',
          'STATUS',
          'KTP',
        ],
        baris: paginatedData.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return _buildWargaRow(
            (((provider.currentPage - 1) * 25) + index + 1).toString(),
            item['nik']?.toString() ?? '-',
            item['nama']?.toString() ?? '-',
            item['jenis_kelamin']?.toString() ?? '-',
            item['no_kk']?.toString() ?? '-',
            item['status_keluarga']?.toString() ?? '-',
            item['domisili']?.toString() ?? 'Tetap',
            item['alamat']?.toString() ?? '-',
            item['has_ktp'] == true || item['has_ktp'] == 'true',
            isAktif: item['is_aktif'] == true || item['is_aktif'] == 'true',
            tanggalLahir: item['tanggal_lahir']?.toString() ?? '-',
            statusPerkawinan: item['status_pernikahan']?.toString() ?? '-',
            agama: item['agama']?.toString() ?? '-',
            item: item,
          );
        }).toList(),
        currentPage: provider.currentPage,
        totalPages: provider.totalPages,
        onPageChanged: (page) {
          context.read<WargaProvider>().fetchWarga(search: _searchQuery, page: page);
        },
      ),
    );
  }

  BarisTabel _buildWargaRow(
    String no,
    String nik,
    String name,
    String gender,
    String kk,
    String hubungan,
    String domisili,
    String address,
    bool hasKtp, {
    bool isAktif = true,
    String tanggalLahir = '-',
    String statusPerkawinan = '-',
    String agama = '-',
    // Data mentah dari backend, dipakai tombol Edit untuk mengisi dialog.
    Map<String, dynamic>? item,
  }) {
    Color domisiliBgColor = const Color(0xFF059669); // Tetap
    String domisiliLower = domisili.toLowerCase();
    if (domisiliLower == 'kos') domisiliBgColor = const Color(0xFFD97706);
    if (domisiliLower == 'kontrak') domisiliBgColor = const Color(0xFF0284C7);

    return BarisTabel(
      sel: [
        SelTabel.teks(
          'NO',
          no,
          sembunyiDiKartu: true,
          gaya: TextStyle(color: context.teksUtama, fontSize: 13),
        ),
        SelTabel.teks(
          'NIK',
          nik,
          gaya: const TextStyle(
            color: Color(0xFFE11D48),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        SelTabel(
          'NAMA LENGKAP',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: name,
                child: SizedBox(
                  // Pemotongan 120px hanya masuk akal di tabel; di kartu nama
                  // memakai lebar yang tersedia.
                  width: pakaiKartu(context) ? null : 120,
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.teksUtama,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Text(gender, style: TextStyle(fontSize: 11, color: context.teksTersier)),
            ],
          ),
          utama: true,
        ),
        SelTabel.teks(
          'NO KK',
          kk,
          gaya: const TextStyle(
            color: Color(0xFF059669),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        SelTabel(
          'STATUS HUBUNGAN',
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: context.garis),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(hubungan, style: TextStyle(fontSize: 11, color: context.teksKedua)),
          ),
        ),
        SelTabel.teks(
          'TGL LAHIR',
          tanggalLahir.isEmpty ? '-' : tanggalLahir,
          gaya: TextStyle(
            color: tanggalLahir.isEmpty || tanggalLahir == '-'
                ? context.garis
                : (context.teksUtama),
            fontSize: 12,
          ),
        ),
        SelTabel.teks(
          'PERKAWINAN',
          statusPerkawinan.isEmpty ? '-' : statusPerkawinan,
          gaya: TextStyle(
            color: statusPerkawinan.isEmpty || statusPerkawinan == '-'
                ? context.garis
                : context.teksKedua,
            fontSize: 12,
          ),
        ),
        SelTabel.teks(
          'AGAMA',
          agama.isEmpty ? '-' : agama,
          gaya: TextStyle(
            color: agama.isEmpty || agama == '-' ? context.garis : context.teksKedua,
            fontSize: 12,
          ),
        ),
        SelTabel(
          'DOMISILI',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: domisiliBgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  domisili,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (address != '-') ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 10, color: Color(0xFFEF4444)),
                    const SizedBox(width: 4),
                    // Flexible: di kartu lebar alamat tidak lagi dipatok 90px,
                    // jadi teksnya harus boleh menyusut mengikuti sisa baris.
                    Flexible(
                      child: Tooltip(
                        message: address.split('\n')[0],
                        child: SizedBox(
                          width: pakaiKartu(context) ? null : 90,
                          child: Text(
                            address.split('\n')[0],
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: context.teksKedua),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        SelTabel(
          'STATUS',
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isAktif ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isAktif ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAktif ? Icons.check_circle_outline : Icons.cancel_outlined,
                  size: 12,
                  color: isAktif ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                ),
                const SizedBox(width: 4),
                Text(
                  isAktif ? 'Aktif' : 'Tidak Aktif',
                  style: TextStyle(
                    color: isAktif ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        SelTabel(
          'KTP',
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: hasKtp ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: hasKtp ? const Color(0xFF22C55E) : const Color(0xFFEF4444)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasKtp ? Icons.check_circle_outline : Icons.cancel_outlined,
                  size: 12,
                  color: hasKtp ? const Color(0xFF16A34A) : const Color(0xFFEF4444),
                ),
                const SizedBox(width: 4),
                Text(
                  hasKtp ? 'Sudah' : 'Belum',
                  style: TextStyle(
                    color: hasKtp ? const Color(0xFF16A34A) : const Color(0xFFEF4444),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      aksi: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ubah data warga. Berada di kiri tombol Akun & Kredensial.
          if (_bolehUbah && item != null)
            IconButton(
              tooltip: 'Edit Data Warga',
              icon: const Icon(Icons.edit_outlined, color: Color(0xFF0F766E), size: 20),
              // Hover presisi: _rapatkanAksi menimpa theme dengan alignment
              // centerLeft + padding 0, sehingga inkwell 48dp lebih lebar dari
              // ikon dan sorotan muncul di area kosong di kanan ikon.
              // Alignment center memusatkan ikon dalam kotak tombolnya.
              style: IconButton.styleFrom(
                alignment: Alignment.center,
                hoverColor: const Color(0xFF0F766E).withValues(alpha: 0.12),
              ),
              onPressed: () => _showEditWargaDialog(context, item),
            ),
          if (_bolehHapus && item != null)
            IconButton(
              tooltip: 'Hapus Warga',
              icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
              style: IconButton.styleFrom(
                alignment: Alignment.center,
                hoverColor: const Color(0xFFEF4444).withValues(alpha: 0.12),
              ),
              onPressed: () => _hapusWarga(context, item),
            ),
          IconButton(
            tooltip: 'Akun & Kredensial',
            icon: const Icon(Icons.manage_accounts_outlined, color: Color(0xFF10B981), size: 20),
            style: IconButton.styleFrom(
              alignment: Alignment.center,
              hoverColor: const Color(0xFF10B981).withValues(alpha: 0.12),
            ),
            onPressed: () => _tampilkanDialogKredensial(context, nik, name),
          ),
        ],
      ),
    );
  }

  Future<void> _tampilkanDialogKredensial(
    BuildContext context,
    String nik,
    String namaWarga,
  ) async {
    final auth = context.read<AuthService>();
    final perm = context.read<PermissionProvider>();
    final userRoleCaller = auth.userRole;

    final bool bolehEditSemua =
        userRoleCaller == 'admin' ||
        userRoleCaller == 'ketua_rt' ||
        userRoleCaller == 'sekretaris' ||
        perm.bolehUbah(_kodeIzin) ||
        perm.bolehTambah(_kodeIzin);
    final bool bolehUbahRole =
        (userRoleCaller == 'admin' || userRoleCaller == 'ketua_rt') && bolehEditSemua;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF10B981))),
    );

    final res = await ApiService.get(ApiConstants.userByNik(nik));
    if (!context.mounted) return;
    Navigator.pop(context);

    if (res['success'] != true) {
      pesanGagal(context, res['message']?.toString() ?? 'Gagal memuat data akun.');
      return;
    }

    final data = res['data'] as Map<String, dynamic>;
    final noHpCtrl = TextEditingController(text: data['no_hp']?.toString() ?? '');
    final passCtrl = TextEditingController();
    String selectedRole = data['role']?.toString() ?? 'warga';
    bool sedangSimpan = false;

    // Sandi disembunyikan secara bawaan, tetapi HARUS bisa dilihat.
    //
    // Yang diketik di sini bukan sandi pengurus sendiri melainkan sandi yang
    // akan ia sampaikan kepada warga — dibacakan lewat telepon atau ditulis di
    // kertas. Tombol mata tetap disediakan agar sandi yang dimasukkan bisa
    // dibaca oleh orang yang perlu menyampaikannya.
    //
    // Tetap tertutup saat dialog dibuka, karena layar ini sering dibuka di
    // depan warga yang bersangkutan maupun orang lain di balai RT.
    bool sandiTerlihat = false;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: context.latarKartu,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Color(0xFFECFDF5), shape: BoxShape.circle),
                  child: const Icon(
                    Icons.manage_accounts_rounded,
                    color: Color(0xFF10B981),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Akun & Kredensial',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: context.teksUtama,
                        ),
                      ),
                      Text(
                        '$namaWarga (NIK: $nik)',
                        style: TextStyle(fontSize: 12, color: context.teksKedua),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const SizedBox(height: 12),
                    if (!bolehEditSemua) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.amber, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Mode Lihat Saja: Akun Anda tidak memiliki izin untuk mengubah data/kredensial warga.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'Username Login',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: context.teksUtama,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: context.latarLembut,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.garis),
                      ),
                      child: Text(
                        data['username']?.toString() ?? nik,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.teksUtama,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nomor HP / WhatsApp',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: context.teksUtama,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: noHpCtrl,
                      enabled: bolehEditSemua,
                      keyboardType: TextInputType.phone,
                      // Dialog ini menulis ke kolom `no_hp` yang sama dengan
                      // formulir Tambah Warga. Menyaring salah satunya saja
                      // berarti huruf tetap bisa masuk lewat pintu yang lain.
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(15),
                      ],
                      style: TextStyle(fontSize: 13, color: context.teksUtama),
                      decoration: InputDecoration(
                        hintText: 'Misal: 081234567890',
                        hintStyle: TextStyle(color: context.teksTersier),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Role / Peran Sistem',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: context.teksUtama,
                          ),
                        ),
                        if (!bolehUbahRole)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Khusus Admin & Ketua RT',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: bolehUbahRole ? context.latarKartu : context.latarLembut,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.garis),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedRole,
                          isExpanded: true,
                          dropdownColor: context.latarKartu,
                          onChanged: bolehUbahRole
                              ? (v) {
                                  if (v != null) setDialogState(() => selectedRole = v);
                                }
                              : null,
                          items: [
                            const DropdownMenuItem(value: 'warga', child: Text('Warga')),
                            const DropdownMenuItem(value: 'ketua_rt', child: Text('Ketua RT')),
                            const DropdownMenuItem(value: 'sekretaris', child: Text('Sekretaris')),
                            const DropdownMenuItem(value: 'bendahara', child: Text('Bendahara')),
                            if (userRoleCaller == 'admin')
                              const DropdownMenuItem(value: 'admin', child: Text('Administrator')),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ubah / Reset Password',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: context.teksUtama,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: passCtrl,
                      enabled: bolehEditSemua,
                      obscureText: !sandiTerlihat,
                      style: TextStyle(fontSize: 13, color: context.teksUtama),
                      decoration: InputDecoration(
                        hintText: bolehEditSemua
                            ? 'Kosongkan jika tidak ingin mengubah'
                            : 'Hanya-baca',
                        hintStyle: TextStyle(color: context.teksTersier),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        suffixIcon: bolehEditSemua
                            ? IconButton(
                                icon: Icon(
                                  sandiTerlihat
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                ),
                                color: context.teksKedua,
                                tooltip: sandiTerlihat
                                    ? 'Sembunyikan sandi'
                                    : 'Tampilkan sandi',
                                onPressed: () =>
                                    setDialogState(() => sandiTerlihat = !sandiTerlihat),
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: sedangSimpan ? null : () => Navigator.pop(dialogCtx),
                child: Text(
                  bolehEditSemua ? 'Batal' : 'Tutup',
                  style: TextStyle(color: context.teksKedua),
                ),
              ),
              if (bolehEditSemua)
                ElevatedButton(
                  onPressed: sedangSimpan
                      ? null
                      : () async {
                          setDialogState(() => sedangSimpan = true);
                          final r = await ApiService.put(
                            ApiConstants.userCredentials,
                            body: {
                              'nik': nik,
                              'no_hp': noHpCtrl.text.trim(),
                              'role': selectedRole,
                              'password': passCtrl.text.trim(),
                            },
                          );

                          if (!dialogCtx.mounted) return;
                          setDialogState(() => sedangSimpan = false);

                          if (r['success'] == true) {
                            Navigator.pop(dialogCtx);
                            if (context.mounted) {
                              pesanSukses(
                                context,
                                r['message']?.toString() ?? 'Kredensial berhasil diperbarui.',
                              );
                              await context.read<WargaProvider>().fetchWarga();
                            }
                          } else {
                            pesanGagal(
                              context,
                              r['message']?.toString() ?? 'Gagal memperbarui kredensial.',
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                  ),
                  child: sedangSimpan
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Simpan Perubahan'),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _importDataWarga(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true, // IMPORTANT for flutter web to get bytes
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes == null) {
          if (context.mounted) {
            pesanGagal(context, 'Gagal membaca file.');
          }
          return;
        }

        final base64String = base64Encode(file.bytes!);

        if (context.mounted) {
          final res = await context.read<WargaProvider>().importWarga(base64String);

          if (!context.mounted) return;

          if (res['success'] == true) {
            tampilkanPesan(
              context,
              res['message'] ?? 'Import berhasil',
              sukses: true,
              // Pesan impor menyebut jumlah baris yang gagal; beri waktu membacanya.
              durasi: const Duration(seconds: 8),
            );
          } else {
            tampilkanPesan(
              context,
              res['message'] ?? 'Gagal import data',
              sukses: false,
              durasi: const Duration(seconds: 8),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        pesanGagal(context, 'Error: $e');
      }
    }
  }

  // Aesthetic input decoration helper, dipakai bersama dialog Tambah & Edit
  // supaya kedua formulir tidak bisa menyimpang rupanya.
  InputDecoration buildDecor(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 14, color: context.teksKedua),
      prefixIcon: Icon(icon, color: const Color(0xFF1B7A6A), size: 20),
      filled: true,
      fillColor: context.latarLembut,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.garis),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.garis),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1B7A6A), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
    );
  }

  /// Dropdown wajib untuk field demografi, dipakai kedua dialog.
  Widget buildDropdownOpsional({
    required String label,
    required IconData icon,
    required String? nilai,
    required List<String> opsi,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: nilai,
      isExpanded: true,
      decoration: buildDecor(label, icon),
      validator: (v) => (v == null || v.isEmpty) ? 'Wajib dipilih' : null,
      hint: Text('Belum dipilih', style: TextStyle(fontSize: 14, color: context.teksTersier)),
      items: opsi
          .map(
            (o) => DropdownMenuItem(
              value: o,
              child: Text(o, style: const TextStyle(fontSize: 14)),
            ),
          )
          .toList(),
      onChanged: onChanged,
      dropdownColor: context.latarKartu,
      borderRadius: BorderRadius.circular(12),
    );
  }

  void _showAddWargaDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nikCtrl = TextEditingController();
    final namaCtrl = TextEditingController();
    final kkCtrl = TextEditingController();
    final hpCtrl = TextEditingController();
    final alamatCtrl = TextEditingController();
    final tanggalLahirCtrl = TextEditingController();
    String jk = 'L';
    String statusHubungan = 'Kepala Keluarga';
    bool hasKtpForm = true;
    // Field demografi bersifat opsional agar alur input cepat tidak terganggu;
    // yang dikosongkan akan muncul sebagai "Tidak Diisi" di layar Statistik.
    String? statusPerkawinan;
    String? agama;
    String? pendidikan;
    String? pekerjaan;
    String? statusRumah;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1B7A6A).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF1B7A6A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tambah Warga Baru',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: context.teksUtama,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: lebarDialog(context, maksimal: 500),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: nikCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(16),
                    ],
                    decoration: buildDecor('Nomor Induk Kependudukan (NIK)', Icons.badge_outlined),
                    validator: (v) {
                      if (v!.isEmpty) return 'Wajib diisi';
                      if (v.length != 16) return 'NIK harus 16 digit';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: namaCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: buildDecor('Nama Lengkap', Icons.person_outline),
                    validator: (v) => v!.isEmpty ? 'Wajib diisi' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: kkCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(16),
                    ],
                    decoration: buildDecor('No Kartu Keluarga (KK)', Icons.contact_page_outlined),
                    validator: (v) {
                      if (v!.isEmpty) return 'Wajib diisi';
                      if (v.length != 16) return 'No KK harus 16 digit';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: jk,
                          decoration: buildDecor('Jenis Kelamin', Icons.wc_outlined),
                          items: const [
                            DropdownMenuItem(
                              value: 'L',
                              child: Text('Laki-laki', style: TextStyle(fontSize: 14)),
                            ),
                            DropdownMenuItem(
                              value: 'P',
                              child: Text('Perempuan', style: TextStyle(fontSize: 14)),
                            ),
                          ],
                          onChanged: (v) => jk = v!,
                          dropdownColor: context.latarKartu,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: hpCtrl,
                          keyboardType: TextInputType.phone,
                          // `keyboardType` hanya MENYARANKAN papan ketik angka,
                          // ia tidak menolak apa pun: papan ketik telepon
                          // Android tetap memuat + * #, dan menempel dari
                          // papan klip maupun papan ketik fisik bisa
                          // memasukkan huruf. Yang benar-benar menyaring
                          // adalah inputFormatters.
                          //
                          // Batas 15 digit mengikuti E.164 dan menjaga kolom
                          // `no_hp` yang bertipe varchar(20) tidak kelebihan.
                          //
                          // Pola yang sama sudah dipakai kolom NIK dan No. KK
                          // di formulir ini; kolom telepon yang tertinggal.
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(15),
                          ],
                          decoration: buildDecor('Nomor HP / WhatsApp', Icons.phone_outlined),
                          validator: (v) {
                            final teks = v?.trim() ?? '';
                            if (teks.isEmpty) return 'Wajib diisi';
                            // Nomor Indonesia terpendek (08xxxxxxxx) sepuluh
                            // digit. Lebih pendek dari itu pasti salah ketik,
                            // dan nomor yang salah berarti pesan WhatsApp
                            // penagihan maupun jadwal ronda tidak pernah
                            // sampai — tanpa ada yang tahu.
                            if (teks.length < 10) return 'Minimal 10 digit';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: alamatCtrl,
                    maxLines: 2,
                    decoration: buildDecor('Alamat / Blok / No. Rumah', Icons.home_outlined),
                    validator: (v) => v!.isEmpty ? 'Wajib diisi' : null,
                  ),
                  const SizedBox(height: 16),
                  // Status Rumah hanya muncul untuk Kepala Keluarga, jadi kedua
                  // dropdown ini harus ikut membangun ulang bersama.
                  StatefulBuilder(
                    builder: (context, setStateHubungan) {
                      return Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: statusHubungan,
                            decoration: buildDecor(
                              'Status Hubungan Keluarga',
                              Icons.family_restroom_outlined,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Kepala Keluarga',
                                child: Text('Kepala Keluarga', style: TextStyle(fontSize: 14)),
                              ),
                              DropdownMenuItem(
                                value: 'Suami',
                                child: Text('Suami', style: TextStyle(fontSize: 14)),
                              ),
                              DropdownMenuItem(
                                value: 'Istri',
                                child: Text('Istri', style: TextStyle(fontSize: 14)),
                              ),
                              DropdownMenuItem(
                                value: 'Anak',
                                child: Text('Anak', style: TextStyle(fontSize: 14)),
                              ),
                              DropdownMenuItem(
                                value: 'Menantu',
                                child: Text('Menantu', style: TextStyle(fontSize: 14)),
                              ),
                              DropdownMenuItem(
                                value: 'Cucu',
                                child: Text('Cucu', style: TextStyle(fontSize: 14)),
                              ),
                              DropdownMenuItem(
                                value: 'Orang Tua',
                                child: Text('Orang Tua', style: TextStyle(fontSize: 14)),
                              ),
                              DropdownMenuItem(
                                value: 'Mertua',
                                child: Text('Mertua', style: TextStyle(fontSize: 14)),
                              ),
                              DropdownMenuItem(
                                value: 'Famili Lain',
                                child: Text('Famili Lain', style: TextStyle(fontSize: 14)),
                              ),
                            ],
                            onChanged: (v) => setStateHubungan(() => statusHubungan = v!),
                            dropdownColor: context.latarKartu,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          if (statusHubungan == 'Kepala Keluarga') ...[
                            const SizedBox(height: 16),
                            buildDropdownOpsional(
                              label: 'Status Rumah (satu per KK)',
                              icon: Icons.house_outlined,
                              nilai: statusRumah,
                              opsi: _opsiStatusRumah,
                              onChanged: (v) => statusRumah = v,
                            ),
                          ],
                        ],
                      );
                    },
                  ),

                  // --- Data demografi (wajib diisi, menjadi sumber grafik Statistik) ---
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.insights_outlined, size: 16, color: Color(0xFF1B7A6A)),
                      const SizedBox(width: 8),
                      Text(
                        'DATA DEMOGRAFI (WAJIB DIISI)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1B7A6A),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: tanggalLahirCtrl,
                    readOnly: true,
                    decoration: buildDecor('Tanggal Lahir', Icons.cake_outlined),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                    onTap: () async {
                      final kini = DateTime.now();
                      final dipilih = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime(kini.year - 25),
                        firstDate: DateTime(1900),
                        lastDate: kini,
                        helpText: 'Pilih Tanggal Lahir',
                      );
                      if (dipilih != null) {
                        tanggalLahirCtrl.text =
                            '${dipilih.year.toString().padLeft(4, '0')}-${dipilih.month.toString().padLeft(2, '0')}-${dipilih.day.toString().padLeft(2, '0')}';
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  buildDropdownOpsional(
                    label: 'Status Perkawinan',
                    icon: Icons.favorite_outline,
                    nilai: statusPerkawinan,
                    opsi: _opsiStatusPerkawinan,
                    onChanged: (v) => statusPerkawinan = v,
                  ),
                  const SizedBox(height: 16),
                  buildDropdownOpsional(
                    label: 'Agama',
                    icon: Icons.mosque_outlined,
                    nilai: agama,
                    opsi: _opsiAgama,
                    onChanged: (v) => agama = v,
                  ),
                  const SizedBox(height: 16),
                  buildDropdownOpsional(
                    label: 'Pendidikan Terakhir',
                    icon: Icons.school_outlined,
                    nilai: pendidikan,
                    opsi: _opsiPendidikan,
                    onChanged: (v) => pendidikan = v,
                  ),
                  const SizedBox(height: 16),
                  buildDropdownOpsional(
                    label: 'Pekerjaan',
                    icon: Icons.work_outline,
                    nilai: pekerjaan,
                    opsi: _opsiPekerjaan,
                    onChanged: (v) => pekerjaan = v,
                  ),
                  const SizedBox(height: 16),
                  StatefulBuilder(
                    builder: (context, setStateBuilder) {
                      return Material(
                        color: context.latarLembut,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: context.garis),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SwitchListTile(
                          title: Text(
                            'Sudah punya e-KTP?',
                            style: TextStyle(fontSize: 14, color: context.teksKedua),
                          ),
                          value: hasKtpForm,
                          activeTrackColor: const Color(0xFF1B7A6A),
                          onChanged: (bool value) {
                            setStateBuilder(() {
                              hasKtpForm = value;
                            });
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: Color(0xFF2563EB), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Informasi Akun',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E3A8A),
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Setelah disimpan, akun login otomatis dibuat dengan NIK sebagai username. '
                                'Sandi awalnya diacak dan ditampilkan SEKALI pada layar berikutnya — catat saat itu juga.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF1E40AF),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              foregroundColor: context.teksKedua,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final provider = context.read<WargaProvider>();
                final result = await provider.tambahWargaLengkap({
                  'nik': nikCtrl.text.trim(),
                  'nama': namaCtrl.text.trim(),
                  'no_kk': kkCtrl.text.trim(),
                  'no_hp': hpCtrl.text.trim(),
                  'alamat': alamatCtrl.text.trim(),
                  'jenis_kelamin': jk,
                  'status_keluarga': statusHubungan,
                  'has_ktp': hasKtpForm,
                  'tanggal_lahir': tanggalLahirCtrl.text.trim(),
                  'status_pernikahan': statusPerkawinan,
                  'agama': agama,
                  'pendidikan': pendidikan,
                  'pekerjaan': pekerjaan,
                  // Status rumah adalah properti KK, hanya diisi lewat Kepala Keluarga.
                  'status_rumah': statusHubungan == 'Kepala Keluarga' ? statusRumah : null,
                });

                if (!ctx.mounted) return;
                Navigator.pop(ctx);

                if (result['success'] == true) {
                  Future.delayed(const Duration(milliseconds: 150), () {
                    if (!context.mounted) return;
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                        title: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_circle,
                                color: Color(0xFF10B981),
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Berhasil Disimpan',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Data warga berhasil ditambahkan ke dalam sistem dan akun akses telah aktif.',
                              style: TextStyle(color: context.teksKedua, fontSize: 14, height: 1.5),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.latarLembut,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: context.garis),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Kredensial Login:',
                                    style: TextStyle(fontSize: 12, color: context.teksKedua),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.person, size: 16, color: context.teksTersier),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Username: ',
                                        style: TextStyle(color: context.teksKedua),
                                      ),
                                      Text(
                                        nikCtrl.text.trim(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: context.teksUtama,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.key, size: 16, color: context.teksTersier),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Password: ',
                                        style: TextStyle(color: context.teksKedua),
                                      ),
                                      // Sandi SUNGGUHAN dari server, bukan
                                      // tulisan tetap.
                                      //
                                      // Kata sandi bawaan seragam untuk semua
                                      // akun baru. Backend mengembalikannya di
                                      // `data.password`; konstanta di sini
                                      // dipakai agar dialog tetap jujur walau
                                      // akun sudah ada lebih dulu (respons
                                      // password-nya null).
                                      SelectableText(
                                        _kataSandiBawaan,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: context.teksUtama,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: const [
                                Icon(Icons.lightbulb_outline, size: 16, color: Color(0xFFD97706)),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Harap berikan informasi login ini kepada warga.',
                                    style: TextStyle(fontSize: 12, color: Color(0xFFD97706)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        actions: [
                          // Tombol hanya muncul bila nomor HP form terisi —
                          // tanpa tujuan, mengirim via gateway tidak masuk akal.
                          if ((hpCtrl.text.trim().isNotEmpty))
                            TextButton.icon(
                              icon: const Icon(Icons.chat_outlined, size: 18),
                              label: const Text('Share WhatsApp'),
                              onPressed: () => _shareKredensialWhatsApp(
                                nik: nikCtrl.text.trim(),
                              ),
                            ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(c),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Selesai',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    );
                  });
                } else {
                  Future.delayed(const Duration(milliseconds: 150), () {
                    if (!context.mounted) return;
                    tampilkanPesan(
                      context,
                      result['message'] ?? 'Gagal menambahkan data warga',
                      sukses: false,
                      perilaku: SnackBarBehavior.floating,
                    );
                  });
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B7A6A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Simpan & Buat Akun', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Dialog untuk mengubah data warga yang sudah ada.
  ///
  /// Formulirnya sama dengan Tambah Warga (supaya kedua jalur menangani kolom
  /// yang sama), tetapi diisi dari `item` yang dikirim backend dan NIK dibuat
  /// hanya-baca — NIK adalah kunci utama anggota sekaligus username akunnya.
  void _showEditWargaDialog(BuildContext context, Map<String, dynamic> item) {
    final formKey = GlobalKey<FormState>();
    final nik = item['nik']?.toString() ?? '';
    final namaCtrl = TextEditingController(text: item['nama']?.toString() ?? '');
    final kkCtrl = TextEditingController(text: item['no_kk']?.toString() ?? '');
    final hpCtrl = TextEditingController(text: item['no_hp']?.toString() ?? '');
    final alamatCtrl = TextEditingController(text: item['alamat']?.toString() ?? '');
    final tanggalLahirCtrl = TextEditingController(text: item['tanggal_lahir']?.toString() ?? '');

    // Backend mengirim label 'Laki-laki'/'Perempuan'; formulir memakai 'L'/'P'.
    String jk = (item['jenis_kelamin']?.toString().startsWith('P') ?? false) ? 'P' : 'L';
    String statusHubungan = item['status_keluarga']?.toString() ?? 'Anggota Keluarga';
    bool hasKtpForm = item['has_ktp'] == true;
    bool isAktifForm = item['is_aktif'] != false;

    String? statusPerkawinan = item['status_pernikahan']?.toString();
    if (statusPerkawinan == null || statusPerkawinan.isEmpty || statusPerkawinan == '-') {
      statusPerkawinan = null;
    }
    String? agama = item['agama']?.toString();
    if (agama == null || agama.isEmpty || agama == '-') agama = null;
    String? pendidikan = item['pendidikan']?.toString();
    if (pendidikan == null || pendidikan.isEmpty || pendidikan == '-') pendidikan = null;
    String? pekerjaan = item['pekerjaan']?.toString();
    if (pekerjaan == null || pekerjaan.isEmpty || pekerjaan == '-') pekerjaan = null;
    String? statusRumah = item['status_rumah']?.toString();
    if (statusRumah == null || statusRumah.isEmpty || statusRumah == '-') statusRumah = null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1B7A6A).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.person_outline, color: Color(0xFF1B7A6A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Edit Data Warga',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: context.teksUtama,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: lebarDialog(context, maksimal: 500),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: nik,
                    readOnly: true,
                    decoration: buildDecor('Nomor Induk Kependudukan (NIK)', Icons.badge_outlined),
                    // NIK kunci utama — form read-only, tapi isinya tetap divalidasi.
                    validator: (v) {
                      if (v!.length != 16) return 'NIK harus 16 digit';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: namaCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: buildDecor('Nama Lengkap', Icons.person_outline),
                    validator: (v) => v!.isEmpty ? 'Wajib diisi' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: kkCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(16),
                    ],
                    decoration: buildDecor('No Kartu Keluarga (KK)', Icons.contact_page_outlined),
                    validator: (v) {
                      if (v!.isEmpty) return 'Wajib diisi';
                      if (v.length != 16) return 'No KK harus 16 digit';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: jk,
                          decoration: buildDecor('Jenis Kelamin', Icons.wc_outlined),
                          items: const [
                            DropdownMenuItem(value: 'L', child: Text('Laki-laki', style: TextStyle(fontSize: 14))),
                            DropdownMenuItem(value: 'P', child: Text('Perempuan', style: TextStyle(fontSize: 14))),
                          ],
                          onChanged: (v) => jk = v!,
                          dropdownColor: context.latarKartu,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: hpCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(15),
                          ],
                          decoration: buildDecor('Nomor HP / WhatsApp', Icons.phone_outlined),
                          validator: (v) {
                            final teks = v?.trim() ?? '';
                            if (teks.isEmpty) return 'Wajib diisi';
                            if (teks.length < 10) return 'Minimal 10 digit';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: alamatCtrl,
                    maxLines: 2,
                    decoration: buildDecor('Alamat / Blok / No. Rumah', Icons.home_outlined),
                    validator: (v) => v!.isEmpty ? 'Wajib diisi' : null,
                  ),
                  const SizedBox(height: 16),
                  // Status Rumah hanya untuk Kepala Keluarga — sama dengan dialog Tambah.
                  StatefulBuilder(
                    builder: (context, setStateHubungan) {
                      return Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: statusHubungan,
                            decoration: buildDecor('Status Hubungan Keluarga', Icons.family_restroom_outlined),
                            items: const [
                              DropdownMenuItem(value: 'Kepala Keluarga', child: Text('Kepala Keluarga', style: TextStyle(fontSize: 14))),
                              DropdownMenuItem(value: 'Suami', child: Text('Suami', style: TextStyle(fontSize: 14))),
                              DropdownMenuItem(value: 'Istri', child: Text('Istri', style: TextStyle(fontSize: 14))),
                              DropdownMenuItem(value: 'Anak', child: Text('Anak', style: TextStyle(fontSize: 14))),
                              DropdownMenuItem(value: 'Menantu', child: Text('Menantu', style: TextStyle(fontSize: 14))),
                              DropdownMenuItem(value: 'Cucu', child: Text('Cucu', style: TextStyle(fontSize: 14))),
                              DropdownMenuItem(value: 'Orang Tua', child: Text('Orang Tua', style: TextStyle(fontSize: 14))),
                              DropdownMenuItem(value: 'Mertua', child: Text('Mertua', style: TextStyle(fontSize: 14))),
                              DropdownMenuItem(value: 'Famili Lain', child: Text('Famili Lain', style: TextStyle(fontSize: 14))),
                            ],
                            onChanged: (v) => setStateHubungan(() => statusHubungan = v!),
                            dropdownColor: context.latarKartu,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          if (statusHubungan == 'Kepala Keluarga') ...[
                            const SizedBox(height: 16),
                            buildDropdownOpsional(
                              label: 'Status Rumah (satu per KK)',
                              icon: Icons.house_outlined,
                              nilai: statusRumah,
                              opsi: _opsiStatusRumah,
                              onChanged: (v) => statusRumah = v,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.insights_outlined, size: 16, color: Color(0xFF1B7A6A)),
                      const SizedBox(width: 8),
                      Text(
                        'DATA DEMOGRAFI (WAJIB DIISI)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1B7A6A),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: tanggalLahirCtrl,
                    readOnly: true,
                    decoration: buildDecor('Tanggal Lahir', Icons.cake_outlined),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                    onTap: () async {
                      final kini = DateTime.now();
                      final parsed = DateTime.tryParse(tanggalLahirCtrl.text);
                      final dipilih = await showDatePicker(
                        context: ctx,
                        initialDate: parsed ?? DateTime(kini.year - 25),
                        firstDate: DateTime(1900),
                        lastDate: kini,
                        helpText: 'Pilih Tanggal Lahir',
                      );
                      if (dipilih != null) {
                        tanggalLahirCtrl.text =
                            '${dipilih.year.toString().padLeft(4, '0')}-${dipilih.month.toString().padLeft(2, '0')}-${dipilih.day.toString().padLeft(2, '0')}';
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  buildDropdownOpsional(
                    label: 'Status Perkawinan',
                    icon: Icons.favorite_outline,
                    nilai: statusPerkawinan,
                    opsi: _opsiStatusPerkawinan,
                    onChanged: (v) => statusPerkawinan = v,
                  ),
                  const SizedBox(height: 16),
                  buildDropdownOpsional(
                    label: 'Agama',
                    icon: Icons.mosque_outlined,
                    nilai: agama,
                    opsi: _opsiAgama,
                    onChanged: (v) => agama = v,
                  ),
                  const SizedBox(height: 16),
                  buildDropdownOpsional(
                    label: 'Pendidikan Terakhir',
                    icon: Icons.school_outlined,
                    nilai: pendidikan,
                    opsi: _opsiPendidikan,
                    onChanged: (v) => pendidikan = v,
                  ),
                  const SizedBox(height: 16),
                  buildDropdownOpsional(
                    label: 'Pekerjaan',
                    icon: Icons.work_outline,
                    nilai: pekerjaan,
                    opsi: _opsiPekerjaan,
                    onChanged: (v) => pekerjaan = v,
                  ),
                  const SizedBox(height: 16),
                  StatefulBuilder(
                    builder: (context, setStateBuilder) {
                      return Material(
                        color: context.latarLembut,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: context.garis),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            SwitchListTile(
                              title: Text(
                                'Sudah punya e-KTP?',
                                style: TextStyle(fontSize: 14, color: context.teksKedua),
                              ),
                              value: hasKtpForm,
                              activeTrackColor: const Color(0xFF1B7A6A),
                              onChanged: (value) => setStateBuilder(() => hasKtpForm = value),
                            ),
                            SwitchListTile(
                              title: Text(
                                'Warga aktif?',
                                style: TextStyle(fontSize: 14, color: context.teksKedua),
                              ),
                              subtitle: Text(
                                'Nonaktif untuk warga yang pindah/keluar.',
                                style: TextStyle(fontSize: 11, color: context.teksTersier),
                              ),
                              value: isAktifForm,
                              activeTrackColor: const Color(0xFF1B7A6A),
                              onChanged: (value) => setStateBuilder(() => isAktifForm = value),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              foregroundColor: context.teksKedua,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final result = await context.read<WargaProvider>().updateWargaLengkap(
                  nik,
                  {
                    'nama': namaCtrl.text.trim(),
                    'no_kk': kkCtrl.text.trim(),
                    'no_hp': hpCtrl.text.trim(),
                    'alamat': alamatCtrl.text.trim(),
                    'jenis_kelamin': jk,
                    'status_keluarga': statusHubungan,
                    'has_ktp': hasKtpForm,
                    'is_aktif': isAktifForm,
                    'tanggal_lahir': tanggalLahirCtrl.text.trim(),
                    'status_pernikahan': statusPerkawinan,
                    'agama': agama,
                    'pendidikan': pendidikan,
                    'pekerjaan': pekerjaan,
                    'status_rumah': statusHubungan == 'Kepala Keluarga' ? statusRumah : null,
                  },
                );

                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                Future.delayed(const Duration(milliseconds: 150), () {
                  if (!context.mounted) return;
                  if (result['success'] == true) {
                    tampilkanPesan(context, 'Data warga berhasil diperbarui.', sukses: true);
                  } else {
                    tampilkanPesan(
                      context,
                      result['message']?.toString() ?? 'Gagal memperbarui data warga.',
                      sukses: false,
                    );
                  }
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B7A6A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Simpan Perubahan', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _hapusWarga(BuildContext context, Map<String, dynamic> item) async {
    final nik = item['nik']?.toString() ?? '';
    final nama = item['nama']?.toString() ?? 'warga ini';

    final ok = await konfirmasiHapus(
      context,
      judul: 'Hapus Data Warga',
      pesan:
          'Hapus $nama (NIK $nik) dari data kependudukan?\n\n'
          'Data warga dan akun loginnya akan dihapus. Riwayat pembayaran dan '
          'transaksi yang sudah tercatat tetap tersimpan.',
    );
    if (!ok || !context.mounted) return;

    final result = await context.read<WargaProvider>().deleteWargaLengkap(nik);
    if (!context.mounted) return;
    tampilkanPesan(
      context,
      result['message']?.toString() ?? 'Selesai.',
      sukses: result['success'] == true,
    );
  }

  /// Kirim kredensial login lewat gateway WhatsApp backend (Fonnte).
  ///
  /// Nama, nomor HP, dan username diambil server dari database berdasarkan
  /// NIK — bukan dikirim dari layar — supaya nomor tujuan selalu data yang
  /// benar dan tidak bisa dicolong untuk kirim ke nomor lain. Pesan disusun
  /// di server (whatsapp.service) memakai sandi bawaan yang sama.
  Future<void> _shareKredensialWhatsApp({required String nik}) async {
    if (nik.isEmpty) return;
    final hasil = await context.read<WargaProvider>().kirimKredensialWA(nik);
    if (!mounted) return;
    tampilkanPesan(
      context,
      hasil['message']?.toString() ?? 'Selesai.',
      sukses: hasil['success'] == true,
    );
  }
}

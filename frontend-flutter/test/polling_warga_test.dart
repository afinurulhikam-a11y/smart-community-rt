import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_community/core/theme/app_theme.dart';
import 'package:smart_community/providers/permission_provider.dart';
import 'package:smart_community/providers/polling_provider.dart';
import 'package:smart_community/screens/admin/polling_warga_screen.dart';

import 'bantuan_uji.dart';

class _PollingTanpaJaringan extends PollingProvider {
  @override
  Future<void> fetchPolling({String? status}) async {}
}

Map<String, dynamic> _pollingFixture({
  int id = 1,
  String judul = 'Pembangunan Pos Ronda Baru di RT 05',
  String deskripsi = 'Musyawarah penentuan lokasi pos ronda baru',
  String status = 'Aktif',
  String tanggalMulai = '2026-08-01',
  String tanggalSelesai = '2026-08-30',
  bool sudahVote = false,
  int? pilihanSaya,
  bool lewatDeadline = false,
  bool belumMulai = false,
}) =>
    {
      'id': id,
      'judul': judul,
      'deskripsi': deskripsi,
      'status': status,
      'tanggal_mulai': tanggalMulai,
      'tanggal_selesai': tanggalSelesai,
      'total_votes': sudahVote ? 1 : 0,
      'sudah_vote': sudahVote,
      'pilihan_saya': pilihanSaya,
      'lewat_deadline': lewatDeadline,
      'belum_mulai': belumMulai,
      'options': [
        {
          'id': 101,
          'polling_id': id,
          'label': 'Lokasi A (Dekat Gerbang Utama)',
          'vote_count': (sudahVote && pilihanSaya == 101) ? 1 : 0,
          'percentage': (sudahVote && pilihanSaya == 101) ? 100 : 0,
        },
        {
          'id': 102,
          'polling_id': id,
          'label': 'Lokasi B (Dekat Taman RT)',
          'vote_count': (sudahVote && pilihanSaya == 102) ? 1 : 0,
          'percentage': (sudahVote && pilihanSaya == 102) ? 100 : 0,
        },
      ],
    };

Widget _susunLayar({
  required List<Map<String, dynamic>> pollingList,
  bool bolehLihat = true,
  bool bolehUbah = true,
  bool gelap = false,
  double skalaFont = 1.0,
}) {
  final provPolling = _PollingTanpaJaringan()..pasangUji(pollingList);
  final provIzin = PermissionProvider();
  if (bolehLihat) {
    provIzin.terapkanData({
      'role': 'warga',
      'role_label': 'Warga',
      'menus': [
        {
          'kode': 'aspirasi.polling',
          'can_view': true,
          'can_create': false,
          'can_update': bolehUbah,
          'can_delete': false,
        },
      ],
    });
  }

  return MultiProvider(
    providers: [
      ...semuaProvider(),
      ChangeNotifierProvider<PollingProvider>.value(value: provPolling),
      ChangeNotifierProvider<PermissionProvider>.value(value: provIzin),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: gelap ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: const PollingWargaScreen(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  group('Polling Warga Widget Test', () {
    testWidgets('Layar menampilkan tombol Berikan Suara saat warga belum memilih', (tester) async {
      final polling = [_pollingFixture(sudahVote: false)];
      await tester.pumpWidget(_susunLayar(pollingList: polling));
      await tester.pumpAndSettle();

      expect(find.text('Pembangunan Pos Ronda Baru di RT 05'), findsOneWidget);
      expect(find.text('Berikan Suara'), findsOneWidget);
      expect(find.text('Ubah Pilihan'), findsNothing);
    });

    testWidgets('Layar menampilkan Pilihan Anda dan tombol Ubah Pilihan saat polling aktif dan sudah memilih', (tester) async {
      final polling = [
        _pollingFixture(
          sudahVote: true,
          pilihanSaya: 101,
        ),
      ];
      await tester.pumpWidget(_susunLayar(pollingList: polling));
      await tester.pumpAndSettle();

      expect(find.text('Pilihan Anda: Lokasi A (Dekat Gerbang Utama)'), findsOneWidget);
      expect(find.text('Ubah Pilihan'), findsOneWidget);
      expect(find.byKey(const Key('tombol_ubah_pilihan')), findsOneWidget);
    });

    testWidgets('Menekan Ubah Pilihan membuka dialog dengan opsi aktif terpilih dan tombol Simpan Perubahan', (tester) async {
      final polling = [
        _pollingFixture(
          sudahVote: true,
          pilihanSaya: 101,
        ),
      ];
      await tester.pumpWidget(_susunLayar(pollingList: polling));
      await tester.pumpAndSettle();

      // Klik tombol Ubah Pilihan
      await tester.tap(find.byKey(const Key('tombol_ubah_pilihan')));
      await tester.pumpAndSettle();

      expect(find.text('Ubah Pilihan'), findsWidgets);
      expect(find.text('Simpan Perubahan'), findsOneWidget);
      expect(find.text('Batal'), findsOneWidget);

      // Tutup dialog
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
    });

    testWidgets('Layar menampilkan status Terkunci tanpa tombol Ubah Pilihan saat polling ditutup', (tester) async {
      final polling = [
        _pollingFixture(
          status: 'Ditutup',
          sudahVote: true,
          pilihanSaya: 102,
        ),
      ];
      await tester.pumpWidget(_susunLayar(pollingList: polling));
      await tester.pumpAndSettle();

      expect(find.text('Pilihan Anda: Lokasi B (Dekat Taman RT) (Terkunci)'), findsOneWidget);
      expect(find.text('Ubah Pilihan'), findsNothing);
    });

    testWidgets('Layar menampilkan status Terkunci saat polling melewati deadline', (tester) async {
      final polling = [
        _pollingFixture(
          status: 'Aktif',
          lewatDeadline: true,
          sudahVote: true,
          pilihanSaya: 101,
        ),
      ];
      await tester.pumpWidget(_susunLayar(pollingList: polling));
      await tester.pumpAndSettle();

      expect(find.text('Pilihan Anda: Lokasi A (Dekat Gerbang Utama) (Terkunci)'), findsOneWidget);
      expect(find.text('Ubah Pilihan'), findsNothing);
    });

    testWidgets('Layar menampilkan status Belum Mulai saat belum_mulai true', (tester) async {
      final polling = [
        _pollingFixture(
          status: 'Aktif',
          belumMulai: true,
          sudahVote: false,
        ),
      ];
      await tester.pumpWidget(_susunLayar(pollingList: polling));
      await tester.pumpAndSettle();

      expect(find.text('Polling belum dimulai.'), findsOneWidget);
      expect(find.text('Berikan Suara'), findsNothing);
      expect(find.text('Ubah Pilihan'), findsNothing);
    });

    testWidgets('Bebas RenderFlex overflow di berbagai ukuran perangkat dan tema gelap', (tester) async {
      final polling = [
        _pollingFixture(
          sudahVote: true,
          pilihanSaya: 101,
        ),
        _pollingFixture(
          id: 2,
          judul: 'Penetapan Jam Malam & Portal RT',
          status: 'Ditutup',
          sudahVote: true,
          pilihanSaya: 102,
        ),
      ];

      for (final k in kondisiUji) {
        for (final gelap in [false, true]) {
          pasangKondisi(tester, k);
          await tester.pumpWidget(_susunLayar(
            pollingList: polling,
            gelap: gelap,
            skalaFont: k.skalaFont,
          ));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull, reason: 'Gagal pada ${k.nama} (gelap: $gelap)');
        }
      }
    });
  });
}

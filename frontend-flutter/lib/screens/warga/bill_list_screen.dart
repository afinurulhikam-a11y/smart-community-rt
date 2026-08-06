import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/bill_provider.dart';
import '../../providers/payment_provider.dart';
import 'payment_screen.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/format.dart';

const Color _hijau = Color(0xFF1B7A6A);

/// Daftar tagihan milik warga, dengan pembayaran online lewat Midtrans.
///
/// Tombol "Tunai" dan "Transfer" yang dulu ada di sini SUDAH DIHAPUS. Keduanya
/// memanggil POST /bills/:id/pay, yang melunasi tagihan seketika DAN memposting
/// pemasukan ke Kas RT — sehingga seorang warga bisa menyatakan dirinya lunas
/// tanpa satu rupiah pun berpindah. Rute itu kini hanya untuk pengurus, yang
/// memakainya mencatat uang yang benar-benar sudah diterima.
///
/// Warga membayar lewat Midtrans, dan tagihan baru lunas setelah backend
/// mengonfirmasi ke server Midtrans.
class BillListScreen extends StatefulWidget {
  const BillListScreen({super.key});
  @override
  State<BillListScreen> createState() => _BillListScreenState();
}

class _BillListScreenState extends State<BillListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;
  final Set<String> _terpilih = {};
  bool _sedangProses = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging && mounted) {
        setState(() {
          _tabIndex = _tabController.index;
          _terpilih.clear();
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BillProvider>().fetchBills();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Dulu `NumberFormat.currency(symbol: 'Rp')` — TANPA spasi, sehingga warga
  // melihat "Rp50.000" di sini dan "Rp 50.000" di dasbornya. Kini satu
  // bentuk untuk seluruh aplikasi; lihat lib/core/format.dart.
  String _rp(num? n) => rupiah(n);

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(teks),
        backgroundColor: sukses ? _hijau : AppTheme.dangerColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _bayar(List<dynamic> semuaBelumLunas) async {
    final dipilih = semuaBelumLunas.where((b) => _terpilih.contains(b.id)).toList();
    if (dipilih.isEmpty) return;

    setState(() => _sedangProses = true);
    final prov = context.read<PaymentProvider>();
    final sesi = await prov.mulai(dipilih.map((b) => b.id as String).toList());

    if (!mounted) return;
    setState(() => _sedangProses = false);

    if (sesi == null) {
      final msg = prov.errorMessage ?? 'Gagal memulai pembayaran.';
      if (msg.contains('berjalan') || msg.contains('batalkan')) {
        _showCancelPendingDialog(semuaBelumLunas);
      } else {
        _pesan(msg, sukses: false);
      }
      return;
    }

    final adaPerubahan = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => PaymentScreen(sesi: sesi)));

    if (!mounted) return;
    _terpilih.clear();
    if (adaPerubahan == true) {
      await context.read<BillProvider>().fetchBills();
    }
  }

  Future<void> _showCancelPendingDialog(List<dynamic> semuaBelumLunas) async {
    final prov = context.read<PaymentProvider>();
    await prov.muatRiwayat();
    final pendingTrx = prov.riwayat.where((r) => r.status == 'pending').toList();

    if (!mounted) return;

    final trxLama = pendingTrx.isNotEmpty ? pendingTrx.first : null;
    final orderId = trxLama?.orderId;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Pembayaran Masih Berjalan'),
        content: Text(
          orderId != null
              ? 'Anda memiliki pembayaran yang belum selesai (Order ID: $orderId).\n\n'
                'Anda dapat melanjutkan pembayaran sebelumnya atau membatalkannya untuk membuat pembayaran baru.'
              : 'Sebagian tagihan memiliki transaksi pembayaran yang sedang berjalan.\n\n'
                'Apakah Anda ingin membatalkan pembayaran sebelumnya?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
          if (trxLama != null && trxLama.redirectUrl != null && trxLama.redirectUrl!.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.payment_rounded, size: 16),
              label: const Text('Lanjutkan Pembayaran'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _hijau,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final adaPerubahan = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => PaymentScreen(sesi: trxLama.toSession())),
                );
                if (!mounted) return;
                _terpilih.clear();
                if (adaPerubahan == true) {
                  await context.read<BillProvider>().fetchBills();
                }
              },
            ),
          if (orderId != null)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                side: const BorderSide(color: Color(0xFFEF4444)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                setState(() => _sedangProses = true);
                final success = await prov.batalkan(orderId);
                if (!mounted) return;
                setState(() => _sedangProses = false);
                if (success) {
                  _pesan('Transaksi lama dibatalkan.', sukses: true);
                  _bayar(semuaBelumLunas);
                } else {
                  _pesan('Gagal membatalkan transaksi.', sukses: false);
                }
              },
              child: const Text('Batalkan & Buat Baru'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final billProvider = context.watch<BillProvider>();
    final belumLunas = billProvider.unpaidBills;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: context.latarLembut,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: context.teksKedua,
            indicator: BoxDecoration(color: _hijau, borderRadius: BorderRadius.circular(12)),
            indicatorSize: TabBarIndicatorSize.tab,
            onTap: (index) {
              setState(() {
                _tabIndex = index;
                _terpilih.clear();
              });
            },
            tabs: const [
              Tab(text: 'Belum Bayar'),
              Tab(text: 'Lunas'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (billProvider.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator(color: _hijau)),
          )
        else
          _tabIndex == 0
              ? _daftar(belumLunas, bisaDipilih: true)
              : _daftar(billProvider.paidBills, bisaDipilih: false),
        if (_terpilih.isNotEmpty) _bilahBayar(belumLunas),
      ],
    );
  }

  Widget _daftar(List bills, {required bool bisaDipilih}) {
    if (bills.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 64,
                color: context.teksKedua.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Text('Tidak ada tagihan', style: TextStyle(color: context.teksKedua)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: bills.length,
      itemBuilder: (ctx, i) => _kartu(bills[i], bisaDipilih),
    );
  }

  Widget _kartu(dynamic bill, bool bisaDipilih) {
    final dipilih = _terpilih.contains(bill.id);
    final warna = bill.isLunas ? AppTheme.successColor : AppTheme.warningColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dipilih ? _hijau : Colors.transparent, width: dipilih ? 1.5 : 0),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: bisaDipilih
            ? () => setState(() {
                if (dipilih) {
                  _terpilih.remove(bill.id);
                } else {
                  _terpilih.add(bill.id as String);
                }
              })
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (bisaDipilih)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    dipilih ? Icons.check_circle : Icons.circle_outlined,
                    color: dipilih ? _hijau : context.garis,
                    size: 22,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: warna.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.check_circle, color: warna),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bill.namaIuran, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      'Periode: ${bill.bulan}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _rp(bill.nominal),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: warna.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      bill.statusLabel,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: warna),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bilahBayar(List belumLunas) {
    final dipilih = belumLunas.where((b) => _terpilih.contains(b.id)).toList();
    final total = dipilih.fold<double>(0, (s, b) => s + (b.nominal as double));

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.latarKartu,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${dipilih.length} tagihan dipilih',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  _rp(total),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _hijau),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _sedangProses ? null : () => _bayar(belumLunas),
            style: ElevatedButton.styleFrom(
              backgroundColor: _hijau,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _sedangProses
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.payment, size: 18),
            label: Text(
              _sedangProses ? 'Menyiapkan...' : 'Bayar Online',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

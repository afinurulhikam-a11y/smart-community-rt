import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/payment_model.dart';
import '../../providers/payment_provider.dart';
import '../../core/theme/warna_konteks.dart';
import '../../core/pesan.dart';

const Color _hijau = Color(0xFF1B7A6A);

/// Halaman pembayaran Midtrans.
///
/// Di Android, halaman Snap ditampilkan langsung di dalam aplikasi memakai
/// WebView. Di Flutter Web hal itu MUSTAHIL — `webview_flutter` tidak punya
/// implementasi web sama sekali — jadi di sana halamannya dibuka di tab baru
/// lewat `url_launcher`, yang sudah menjadi dependensi proyek ini.
///
/// Apa pun jalurnya, yang menentukan tagihan lunas tetap backend: layar ini
/// hanya menyediakan tombol Periksa Status, dan backend yang bertanya ke
/// server Midtrans.
class PaymentScreen extends StatefulWidget {
  final PaymentSession sesi;

  const PaymentScreen({super.key, required this.sesi});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  WebViewController? _webView;
  bool _memuat = true;
  bool _sedangPeriksa = false;
  PaymentStatus? _status;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _memuat = false;
      // Buka di tab baru; pengguna kembali ke aplikasi setelah membayar.
      WidgetsBinding.instance.addPostFrameCallback((_) => _bukaDiBrowser());
    } else {
      _siapkanWebView();
    }
  }

  void _siapkanWebView() {
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _memuat = false);
          },
          onNavigationRequest: (permintaan) {
            // Snap mengarahkan ke MIDTRANS_FINISH_URL setelah selesai. Begitu
            // itu terjadi, langsung tanyakan status yang sebenarnya.
            if (permintaan.url.contains('/payments/selesai')) {
              _periksaStatus();
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.sesi.redirectUrl));
  }

  Future<void> _bukaDiBrowser() async {
    final ok = await launchUrl(
      Uri.parse(widget.sesi.redirectUrl),
      webOnlyWindowName: '_blank',
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      _pesan('Gagal membuka halaman pembayaran.', sukses: false);
    }
  }

  Future<void> _periksaStatus() async {
    if (_sedangPeriksa) return;
    setState(() => _sedangPeriksa = true);

    final hasil = await context.read<PaymentProvider>().periksa(widget.sesi.orderId);
    if (!mounted) return;

    setState(() {
      _sedangPeriksa = false;
      _status = hasil;
    });

    if (hasil == null) {
      _pesan(
        context.read<PaymentProvider>().errorMessage ?? 'Gagal memeriksa status.',
        sukses: false,
      );
      return;
    }

    if (hasil.lunas) {
      _pesan('Pembayaran berhasil. Tagihan Anda sudah lunas.');
      // true = ada perubahan, daftar tagihan perlu dimuat ulang.
      Navigator.of(context).pop(true);
    } else if (hasil.menunggu) {
      _pesan('Pembayaran belum selesai. Selesaikan lalu periksa lagi.', sukses: false);
    } else {
      _pesan('Pembayaran ${hasil.label.toLowerCase()}. Tagihan bisa dibayar ulang.', sukses: false);
      Navigator.of(context).pop(true);
    }
  }

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    tampilkanPesan(
      context,
      teks,
      sukses: sukses,
      perilaku: SnackBarBehavior.floating,
      durasi: const Duration(seconds: 5),
    );
  }

  String get _rupiah {
    final n = widget.sesi.grossAmount.toInt().toString();
    final b = StringBuffer();
    for (int i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) b.write('.');
      b.write(n[i]);
    }
    return 'Rp $b';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _hijau,
        foregroundColor: Colors.white,
        title: const Text('Pembayaran Iuran'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          // Kembali tanpa menyimpulkan apa pun; daftar tetap dimuat ulang
          // karena statusnya bisa saja sudah berubah di sisi Midtrans.
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ),
      body: Column(
        children: [
          _ringkasan(),
          Expanded(child: kIsWeb ? _tampilanWeb() : _tampilanWebView()),
          _bilahBawah(),
        ],
      ),
    );
  }

  Widget _ringkasan() {
    return Container(
      width: double.infinity,
      color: _hijau,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.sesi.jumlahTagihan} tagihan',
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 2),
          Text(
            _rupiah,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Kode pesanan: ${widget.sesi.orderId}',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _tampilanWebView() {
    return Stack(
      children: [
        WebViewWidget(controller: _webView!),
        if (_memuat) const Center(child: CircularProgressIndicator(color: _hijau)),
      ],
    );
  }

  /// Di web, halaman Snap ada di tab lain — jadi di sini hanya penunjuk arah.
  Widget _tampilanWeb() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_in_new, size: 56, color: _hijau),
            const SizedBox(height: 20),
            const Text(
              'Pembayaran dibuka di tab baru',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Selesaikan pembayaran di tab tersebut, lalu kembali ke sini '
              'dan tekan Periksa Status.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: context.teksKedua),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _bukaDiBrowser,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Buka Ulang Halaman Pembayaran'),
              style: OutlinedButton.styleFrom(foregroundColor: _hijau),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bilahBawah() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.latarKartu,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_status != null && !_status!.lunas)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _status!.label,
                  style: TextStyle(fontSize: 12, color: context.teksKedua),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sedangPeriksa ? null : _periksaStatus,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hijau,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _sedangPeriksa
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.verified_outlined, size: 18),
                label: Text(
                  _sedangPeriksa ? 'Memeriksa...' : 'Periksa Status Pembayaran',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

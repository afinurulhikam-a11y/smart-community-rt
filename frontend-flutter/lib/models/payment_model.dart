/// Hasil memulai pembayaran — bekal untuk membuka halaman Midtrans.
class PaymentSession {
  final String orderId;
  final String snapToken;
  final String redirectUrl;
  final double grossAmount;
  final int jumlahTagihan;

  const PaymentSession({
    required this.orderId,
    required this.snapToken,
    required this.redirectUrl,
    required this.grossAmount,
    required this.jumlahTagihan,
  });

  factory PaymentSession.fromJson(Map<String, dynamic> j) => PaymentSession(
    orderId: j['order_id']?.toString() ?? '',
    snapToken: j['snap_token']?.toString() ?? '',
    redirectUrl: j['redirect_url']?.toString() ?? '',
    grossAmount: (j['gross_amount'] as num?)?.toDouble() ?? 0,
    jumlahTagihan: (j['jumlah_tagihan'] as num?)?.toInt() ?? 0,
  );
}

/// Status sebuah pembayaran, selalu berasal dari backend yang menanyakannya
/// ke Midtrans — aplikasi tidak pernah menyimpulkan sendiri.
class PaymentStatus {
  final String orderId;
  final String status;
  final String? paymentType;
  final double grossAmount;
  final bool lunas;

  const PaymentStatus({
    required this.orderId,
    required this.status,
    this.paymentType,
    required this.grossAmount,
    required this.lunas,
  });

  bool get menunggu => status == 'pending';
  bool get gagal => !lunas && !menunggu;

  String get label {
    if (lunas) return 'Lunas';
    if (menunggu) return 'Menunggu pembayaran';
    switch (status) {
      case 'expire':
        return 'Kedaluwarsa';
      case 'cancel':
        return 'Dibatalkan';
      case 'deny':
        return 'Ditolak';
      default:
        return 'Gagal';
    }
  }

  factory PaymentStatus.fromJson(Map<String, dynamic> j) => PaymentStatus(
    orderId: j['order_id']?.toString() ?? '',
    status: j['status']?.toString() ?? 'pending',
    paymentType: j['payment_type']?.toString(),
    grossAmount: (j['gross_amount'] as num?)?.toDouble() ?? 0,
    lunas: j['lunas'] == true,
  );
}

/// Satu baris riwayat pembayaran.
class PaymentRiwayat {
  final String orderId;
  final String status;
  final double grossAmount;
  final String? paymentType;
  final String? snapToken;
  final String? redirectUrl;
  final String? namaPembayar;
  final int jumlahTagihan;
  final DateTime? dibuat;
  final DateTime? lunasPada;

  const PaymentRiwayat({
    required this.orderId,
    required this.status,
    required this.grossAmount,
    this.paymentType,
    this.snapToken,
    this.redirectUrl,
    this.namaPembayar,
    required this.jumlahTagihan,
    this.dibuat,
    this.lunasPada,
  });

  bool get lunas => status == 'settlement';

  PaymentSession toSession() => PaymentSession(
    orderId: orderId,
    snapToken: snapToken ?? '',
    redirectUrl: redirectUrl ?? '',
    grossAmount: grossAmount,
    jumlahTagihan: jumlahTagihan,
  );

  factory PaymentRiwayat.fromJson(Map<String, dynamic> j) => PaymentRiwayat(
    orderId: j['order_id']?.toString() ?? '',
    status: j['status']?.toString() ?? '',
    grossAmount: double.tryParse(j['gross_amount']?.toString() ?? '') ?? 0,
    paymentType: j['payment_type']?.toString(),
    snapToken: j['snap_token']?.toString(),
    redirectUrl: j['redirect_url']?.toString(),
    namaPembayar: j['nama_pembayar']?.toString(),
    jumlahTagihan: (j['jumlah_tagihan'] as num?)?.toInt() ?? 0,
    dibuat: DateTime.tryParse(j['created_at']?.toString() ?? ''),
    lunasPada: DateTime.tryParse(j['settled_at']?.toString() ?? ''),
  );
}

import 'package:flutter/material.dart';
import '../core/theme/warna_konteks.dart';

/// Tombol kembali berbentuk ikon di sebelah kiri breadcrumb / ikon modul.
class TombolKembali extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;

  const TombolKembali({
    super.key,
    this.onPressed,
    this.tooltip = 'Kembali ke halaman sebelumnya',
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed ?? () => Navigator.maybePop(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.latarLembut,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.garis),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            color: context.teksUtama,
            size: 18,
          ),
        ),
      ),
    );
  }
}

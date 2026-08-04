import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/finance_provider.dart';
import '../../core/theme/warna_konteks.dart';

class FinanceReportScreen extends StatefulWidget {
  const FinanceReportScreen({super.key});
  @override
  State<FinanceReportScreen> createState() => _FinanceReportScreenState();
}

class _FinanceReportScreenState extends State<FinanceReportScreen> {
  @override
  void initState() {
    super.initState();
    context.read<FinanceProvider>().fetchTransactions();
    context.read<FinanceProvider>().fetchSummary();
  }

  @override
  Widget build(BuildContext context) {
    final finance = context.watch<FinanceProvider>();
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        if (finance.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          // Summary Cards
          if (finance.summary != null)
            Row(
              children: [
                _buildSummaryCard(
                  'Pemasukan',
                  currencyFormat.format(finance.summary!.totalPemasukan),
                  Icons.arrow_downward,
                  const Color(0xFF059669),
                ),
                const SizedBox(width: 12),
                _buildSummaryCard(
                  'Pengeluaran',
                  currencyFormat.format(finance.summary!.totalPengeluaran),
                  Icons.arrow_upward,
                  const Color(0xFFDC2626),
                ),
                const SizedBox(width: 12),
                _buildSummaryCard(
                  'Saldo',
                  currencyFormat.format(finance.summary!.saldo),
                  Icons.account_balance,
                  const Color(0xFF1B7A6A),
                ),
              ],
            ),
          const SizedBox(height: 24),

          // Transaction History Title
          const Text(
            'Riwayat Keuangan RT',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Transparan untuk seluruh warga',
            style: TextStyle(fontSize: 13, color: context.teksKedua),
          ),
          const SizedBox(height: 12),

          // Transactions List
          finance.transactions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 48,
                          color: AppTheme.textSecondary.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Belum ada data keuangan',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: finance.transactions.length,
                  itemBuilder: (ctx, i) {
                    final tx = finance.transactions[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.latarKartu,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color:
                                  (tx.isPemasukan
                                          ? AppTheme.successColor
                                          : AppTheme.dangerColor)
                                      .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              tx.isPemasukan ? Icons.arrow_downward : Icons.arrow_upward,
                              color: tx.isPemasukan
                                  ? AppTheme.successColor
                                  : AppTheme.dangerColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tx.deskripsi,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${tx.kategori} · ${DateFormat('dd MMM yyyy').format(tx.tanggal)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${tx.isPemasukan ? '+' : '-'}${currencyFormat.format(tx.jumlah)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: tx.isPemasukan
                                  ? AppTheme.successColor
                                  : AppTheme.dangerColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ],
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.latarKartu,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(fontSize: 12, color: context.teksKedua)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

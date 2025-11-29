import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../models/bulletin_model.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _filterStatus = 'all'; // all, completed, analyzing, failed

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final userId = authProvider.user?.uid;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Geçmiş Analizler')),
        body: const Center(child: Text('Giriş yapılmamış')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Geçmiş Analizler'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() => _filterStatus = value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all',
                child: Text('Tümü'),
              ),
              const PopupMenuItem(
                value: 'completed',
                child: Text('Tamamlananlar'),
              ),
              const PopupMenuItem(
                value: 'analyzing',
                child: Text('İşlenenler'),
              ),
              const PopupMenuItem(
                value: 'failed',
                child: Text('Başarısızlar'),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _buildQuery(userId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildError(context, snapshot.error.toString());
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final bulletins = snapshot.data?.docs ?? [];

          if (bulletins.isEmpty) {
            return _buildEmpty(context);
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {});
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: bulletins.length,
              itemBuilder: (context, index) {
                final doc = bulletins[index];
                final bulletin = BulletinModel.fromFirestore(doc);
                
                return _buildBulletinCard(context, bulletin);
              },
            ),
          );
        },
      ),
    );
  }

  // Filtreye göre query oluştur
  Stream<QuerySnapshot> _buildQuery(String userId) {
    Query query = FirebaseFirestore.instance
        .collection('bulletins')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50);

    if (_filterStatus != 'all') {
      query = query.where('status', isEqualTo: _filterStatus);
    }

    return query.snapshots();
  }

  // Bülten Kartı
  Widget _buildBulletinCard(BuildContext context, BulletinModel bulletin) {
    final status = _getStatusInfo(bulletin.status);
    final hasResults = bulletin.status == 'completed' && bulletin.analysis != null;
    
    // Başarı oranını hesapla
    double? successRate;
    if (hasResults) {
      try {
        final analysis = BulletinAnalysis.fromJson(bulletin.analysis!);
        successRate = analysis.overall.successProbability;
      } catch (e) {
        // Parse hatası
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: status['color'].withOpacity(0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (bulletin.status == 'completed' || bulletin.status == 'analyzing') {
            context.push('/analysis/${bulletin.id}');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Bu analiz henüz tamamlanmadı'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst satır: Tarih + Status Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Tarih
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatDate(bulletin.createdAt),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  
                  // Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: status['color'].withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: status['color'].withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          status['icon'],
                          size: 14,
                          color: status['color'],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          status['text'],
                          style: TextStyle(
                            color: status['color'],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),

              // Başarı Oranı (sadece completed için)
              if (hasResults && successRate != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Başarı Olasılığı',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                '%${successRate.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: _getSuccessColor(successRate),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: successRate / 100,
                                    backgroundColor: Colors.grey[200],
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _getSuccessColor(successRate),
                                    ),
                                    minHeight: 8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    // Maç sayısı
                    _buildInfoChip(
                      context,
                      icon: Icons.sports_soccer,
                      label: '${_getMatchCount(bulletin)} Maç',
                      color: Colors.blue,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // Alt satır: Aksiyon butonları
              Row(
                children: [
                  // Görüntüle butonu
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        context.push('/analysis/${bulletin.id}');
                      },
                      icon: const Icon(Icons.visibility, size: 18),
                      label: const Text('Görüntüle'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        side: BorderSide(color: Theme.of(context).primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // Sil butonu
                  IconButton(
                    onPressed: () => _showDeleteDialog(context, bulletin),
                    icon: const Icon(Icons.delete_outline),
                    color: Colors.red,
                    style: IconButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
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

  // Bilgi Chip
  Widget _buildInfoChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // Boş durum
  Widget _buildEmpty(BuildContext context) {
    String message;
    String description;

    switch (_filterStatus) {
      case 'completed':
        message = 'Tamamlanmış analiz yok';
        description = 'Henüz tamamlanmış bir analiz bulunmuyor';
        break;
      case 'analyzing':
        message = 'İşlenen analiz yok';
        description = 'Şu anda işlenen bir analiz bulunmuyor';
        break;
      case 'failed':
        message = 'Başarısız analiz yok';
        description = 'Başarısız olan bir analiz bulunmuyor';
        break;
      default:
        message = 'Henüz analiz yok';
        description = 'İlk analizinizi yapmak için bülten yükleyin';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.grey[700],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          if (_filterStatus == 'all')
            ElevatedButton.icon(
              onPressed: () => context.push('/upload'),
              icon: const Icon(Icons.add),
              label: const Text('Yeni Analiz'),
            ),
        ],
      ),
    );
  }

  // Hata durumu
  Widget _buildError(BuildContext context, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 80,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              'Bir Hata Oluştu',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  // Silme onayı
  Future<void> _showDeleteDialog(BuildContext context, BulletinModel bulletin) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Analizi Sil'),
          content: const Text('Bu analizi silmek istediğinize emin misiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                
                try {
                  await FirebaseFirestore.instance
                      .collection('bulletins')
                      .doc(bulletin.id)
                      .delete();
                  
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Analiz silindi'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Silme hatası: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text(
                'Sil',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  // Helper Functions
  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'completed':
        return {
          'icon': Icons.check_circle,
          'text': 'Tamamlandı',
          'color': Colors.green,
        };
      case 'analyzing':
        return {
          'icon': Icons.hourglass_empty,
          'text': 'İşleniyor',
          'color': Colors.orange,
        };
      case 'failed':
        return {
          'icon': Icons.error,
          'text': 'Başarısız',
          'color': Colors.red,
        };
      case 'pending':
        return {
          'icon': Icons.pending,
          'text': 'Beklemede',
          'color': Colors.blue,
        };
      default:
        return {
          'icon': Icons.help,
          'text': 'Bilinmiyor',
          'color': Colors.grey,
        };
    }
  }

  Color _getSuccessColor(double rate) {
    if (rate >= 70) return Colors.green;
    if (rate >= 50) return Colors.orange;
    return Colors.red;
  }

  int _getMatchCount(BulletinModel bulletin) {
    if (bulletin.analysis == null) return 0;
    
    try {
      final analysis = BulletinAnalysis.fromJson(bulletin.analysis!);
      return analysis.predictions.length;
    } catch (e) {
      return 0;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      // Bugün
      return 'Bugün ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      // Dün
      return 'Dün ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      // Son 7 gün
      final days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
      return '${days[date.weekday - 1]} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      // Eski tarih
      return '${date.day}.${date.month}.${date.year}';
    }
  }
}
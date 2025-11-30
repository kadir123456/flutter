import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paketler'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Kredi Paketleri'),
            Tab(text: 'Premium Abonelik'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCreditPackages(context),
          _buildPremiumPackages(context),
        ],
      ),
    );
  }

  Widget _buildCreditPackages(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    final packages = [
      {
        'credits': 5,
        'price': 29.99,
        'bonus': 0,
        'popular': false,
        'color': Colors.blue,
      },
      {
        'credits': 10,
        'price': 49.99,
        'bonus': 2,
        'popular': true,
        'color': Colors.purple,
      },
      {
        'credits': 25,
        'price': 99.99,
        'bonus': 5,
        'popular': false,
        'color': Colors.orange,
      },
      {
        'credits': 50,
        'price': 179.99,
        'bonus': 15,
        'popular': false,
        'color': Colors.green,
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mevcut Kredi
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withValues(alpha: 0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(Icons.stars, color: Colors.white, size: 48),
                const SizedBox(height: 12),
                Text(
                  '${authProvider.credits}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Mevcut Kredi',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Kredi Paketleri',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Daha fazla analiz yapmak için kredi satın alın',
            style: TextStyle(color: Colors.grey[600]),
          ),

          const SizedBox(height: 16),

          // Kredi Paketleri
          ...packages.map((package) => _buildCreditPackageCard(
                context,
                credits: package['credits'] as int,
                price: package['price'] as double,
                bonus: package['bonus'] as int,
                isPopular: package['popular'] as bool,
                color: package['color'] as Color,
              )),
        ],
      ),
    );
  }

  Widget _buildCreditPackageCard(
    BuildContext context, {
    required int credits,
    required double price,
    required int bonus,
    required bool isPopular,
    required Color color,
  }) {
    final totalCredits = credits + bonus;
    final hasBonus = bonus > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPopular ? color : Colors.grey[300]!,
          width: isPopular ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          // Popüler Badge
          if (isPopular)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: const Text(
                  'EN POPÜLER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // İkon ve Kredi
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.stars, color: color, size: 32),
                      const SizedBox(height: 4),
                      Text(
                        '$totalCredits',
                        style: TextStyle(
                          color: color,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Kredi',
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // Detaylar
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$credits Kredi Paketi',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (hasBonus)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green[300]!),
                          ),
                          child: Text(
                            '+$bonus Bonus Kredi',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '₺${price.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '(₺${(price / totalCredits).toStringAsFixed(2)}/kredi)',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Satın Al Butonu
                ElevatedButton(
                  onPressed: () => _handleCreditPurchase(context, credits, price),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Satın Al'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumPackages(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    if (authProvider.isPremium) {
      return _buildAlreadyPremium(context);
    }

    final packages = [
      {
        'duration': 'Aylık',
        'days': 30,
        'price': 899.00,
        'color': Colors.blue,
        'icon': Icons.calendar_today,
      },
      {
        'duration': '3 Aylık',
        'days': 90,
        'price': 1999.00,
        'color': Colors.purple,
        'icon': Icons.calendar_month,
        'popular': true,
        'discount': '%26 İndirim',
      },
      {
        'duration': 'Yıllık',
        'days': 365,
        'price': 6999.00,
        'color': Colors.amber,
        'icon': Icons.event_available,
        'discount': '%35 İndirim',
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Premium Özellikleri
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.workspace_premium, color: Colors.white, size: 32),
                    SizedBox(width: 12),
                    Text(
                      'Premium Üyelik',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildFeature('Sınırsız analiz yapma hakkı'),
                _buildFeature('Reklamsız deneyim'),
                _buildFeature('Öncelikli müşteri desteği'),
                _buildFeature('Gelişmiş istatistikler'),
                _buildFeature('Özel analizler ve raporlar'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Premium Paketleri',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tüm özelliklere sınırsız erişim',
            style: TextStyle(color: Colors.grey[600]),
          ),

          const SizedBox(height: 16),

          // Premium Paketleri
          ...packages.map((package) => _buildPremiumPackageCard(
                context,
                duration: package['duration'] as String,
                days: package['days'] as int,
                price: package['price'] as double,
                color: package['color'] as Color,
                icon: package['icon'] as IconData,
                isPopular: package['popular'] as bool? ?? false,
                discount: package['discount'] as String?,
              )),
        ],
      ),
    );
  }

  Widget _buildFeature(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumPackageCard(
    BuildContext context, {
    required String duration,
    required int days,
    required double price,
    required Color color,
    required IconData icon,
    required bool isPopular,
    String? discount,
  }) {
    final monthlyPrice = price / (days / 30);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPopular ? color : Colors.grey[300]!,
          width: isPopular ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          if (isPopular)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: const Text(
                  'EN POPÜLER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            duration,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (discount != null)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.green[300]!),
                              ),
                              child: Text(
                                discount,
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₺${price.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '₺${monthlyPrice.toStringAsFixed(2)}/ay',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _handlePremiumPurchase(context, days, price),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Premium Ol - $duration',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlreadyPremium(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final userModel = authProvider.userModel;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.workspace_premium,
                size: 80,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Premium Üyesiniz!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tüm premium özelliklerden yararlanıyorsunuz',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
            if (userModel?.premiumExpiresAt != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.calendar_today, color: Colors.grey[700]),
                    const SizedBox(height: 8),
                    Text(
                      'Bitiş Tarihi',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(userModel!.premiumExpiresAt!),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _handleCreditPurchase(BuildContext context, int credits, double price) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue[700]),
            const SizedBox(width: 12),
            const Text('Bilgilendirme'),
          ],
        ),
        content: const Text(
          'Ödeme sistemi yakında eklenecek.\n\nGoogle Play üzerinden güvenli ödeme altyapısı ile kredi satın alabileceksiniz.',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  void _handlePremiumPurchase(BuildContext context, int days, double price) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue[700]),
            const SizedBox(width: 12),
            const Text('Bilgilendirme'),
          ],
        ),
        content: const Text(
          'Ödeme sistemi yakında eklenecek.\n\nGoogle Play üzerinden güvenli ödeme altyapısı ile premium abonelik satın alabileceksiniz.',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
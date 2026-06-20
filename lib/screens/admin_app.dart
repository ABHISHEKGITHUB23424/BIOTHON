import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../main.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _currentTab = 0;
  bool _isLoading = false;
  Map<String, dynamic> _inventory = {};
  Map<String, double> _bssiScores = {};
  List _alertHistory = [];
  List _redistributions = [];

  List<String> _bloodGroupsOrder = ["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"];
  String _activeSort = 'default';

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    final state = Provider.of<AppState>(context, listen: false);
    if (state.bankId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      // 1. Fetch Inventory Stock
      final invRes = await http.get(Uri.parse('${state.backendUrl}/inventory/${state.bankId}'));
      // 2. Fetch BSSI Scores
      final bssiRes = await http.get(Uri.parse('${state.backendUrl}/bssi/${state.bankId}'));
      // 3. Fetch Alert History
      final alertRes = await http.get(Uri.parse('${state.backendUrl}/alerts/history/${state.bankId}'));
      
      if (invRes.statusCode == 200 && bssiRes.statusCode == 200) {
        final Map<String, dynamic> invData = jsonDecode(invRes.body);
        final Map<String, dynamic> bssiData = jsonDecode(bssiRes.body);
        
        setState(() {
          _inventory = invData;
          _bssiScores = bssiData.map((key, value) => MapEntry(key, (value as num).toDouble()));
          if (alertRes.statusCode == 200) {
            _alertHistory = jsonDecode(alertRes.body);
          }
          _applyActiveSort();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      print("Error refreshing admin dashboard: $e");
    }
  }

  void _applyActiveSort() {
    if (_activeSort == 'bssi') {
      _bloodGroupsOrder.sort((a, b) {
        final bssiA = _bssiScores[a] ?? 0.0;
        final bssiB = _bssiScores[b] ?? 0.0;
        return bssiB.compareTo(bssiA);
      });
    } else if (_activeSort == 'stock') {
      _bloodGroupsOrder.sort((a, b) {
        final stockA = (_inventory[a] ?? {'units_available': 0.0})['units_available'] as num;
        final stockB = (_inventory[b] ?? {'units_available': 0.0})['units_available'] as num;
        return stockA.compareTo(stockB);
      });
    }
  }

  Color _getBssiColor(double score) {
    if (score <= 30) return const Color(0xFF30D158); // Green
    if (score <= 55) return const Color(0xFFFFCC00); // Yellow
    if (score <= 75) return const Color(0xFFFF9F0A); // Orange
    if (score <= 90) return const Color(0xFFFF3B30); // Red
    return const Color(0xFF8B0000); // Dark Red (Emergency)
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);

    final List<Widget> tabs = [
      _buildGridDashboard(state),
      _buildRedistributionsTab(state),
      _buildAlertHistoryTab(state),
      _buildUpdateInventoryTab(state),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('${state.name} Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => state.logout(),
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30)))
          : tabs[_currentTab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        selectedItemColor: const Color(0xFFFF3B30),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (idx) => setState(() => _currentTab = idx),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: 'Redistribution'),
          BottomNavigationBarItem(icon: Icon(Icons.notification_important_outlined), label: 'Alerts Log'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), label: 'Log Transaction'),
        ],
      ),
    );
  }

  // --- TAB 1: 8-CELL GRID INVENTORY ---
  Widget _buildGridDashboard(AppState state) {
    double totalUnits = 0.0;
    _inventory.forEach((key, val) {
      totalUnits += (val['units_available'] ?? 0.0) as double;
    });

    int criticalCount = 0;
    _bssiScores.forEach((key, val) {
      if (val > 75.0) criticalCount++;
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row with Title and Dynamic Sort Menu
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 850) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Inventory & Shortage Severity Index (BSSI)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    _buildSortRow(),
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Inventory & Shortage Severity Index (BSSI)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildSortRow(),
                    ),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 16),

          // Overview Dashboard Cards
          _buildSummaryCards(totalUnits, criticalCount),
          const SizedBox(height: 20),

          // Instructions for manual rearranging
          Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: Colors.white.withOpacity(0.35)),
              const SizedBox(width: 6),
              Text(
                'Tip: Long-press and drag any card to manually rearrange your dashboard',
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double width = constraints.maxWidth;
                final int crossAxisCount = width > 1100 ? 4 : (width > 750 ? 3 : 2);
                final double cardWidth = (width - (crossAxisCount - 1) * 16) / crossAxisCount;
                final double childAspectRatio = cardWidth / 160.0; // Fixed 160px height to prevent desktop clipping
                
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: childAspectRatio,
                  ),
                  itemCount: _bloodGroupsOrder.length,
                  itemBuilder: (context, index) {
                    final bg = _bloodGroupsOrder[index];
                    final stock = _inventory[bg] ?? {'units_available': 0.0, 'units_expiring_3days': 0.0};
                    final bssi = _bssiScores[bg] ?? 20.0;
                    final cellColor = _getBssiColor(bssi);
                    
                    return DragTarget<String>(
                      onWillAccept: (data) => data != bg,
                      onAccept: (receivedBg) {
                        setState(() {
                          _activeSort = 'custom';
                          final int oldIndex = _bloodGroupsOrder.indexOf(receivedBg);
                          final int newIndex = _bloodGroupsOrder.indexOf(bg);
                          _bloodGroupsOrder.removeAt(oldIndex);
                          _bloodGroupsOrder.insert(newIndex, receivedBg);
                        });
                      },
                      builder: (context, candidateData, rejectedData) {
                        final bool isOver = candidateData.isNotEmpty;
                        
                        return LongPressDraggable<String>(
                          data: bg,
                          feedback: Material(
                            color: Colors.transparent,
                            child: Opacity(
                              opacity: 0.8,
                              child: SizedBox(
                                width: cardWidth,
                                height: 160,
                                child: HoverableBloodGroupCard(
                                  bloodGroup: bg,
                                  stock: stock,
                                  bssi: bssi,
                                  cellColor: cellColor,
                                  onTap: () {},
                                  index: index,
                                ),
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.2,
                            child: HoverableBloodGroupCard(
                              bloodGroup: bg,
                              stock: stock,
                              bssi: bssi,
                              cellColor: cellColor,
                              onTap: () {},
                              index: index,
                            ),
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: isOver 
                                  ? Border.all(color: cellColor, width: 2) 
                                  : Border.all(color: Colors.transparent, width: 2),
                            ),
                            child: HoverableBloodGroupCard(
                              key: ValueKey(bg),
                              bloodGroup: bg,
                              stock: stock,
                              bssi: bssi,
                              cellColor: cellColor,
                              index: index,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => BloodGroupDetailScreen(
                                      bankId: state.bankId!,
                                      bloodGroup: bg,
                                      currentStock: stock['units_available'],
                                      expiringStock: stock['units_expiring_3days'],
                                      bssiScore: bssi,
                                    ),
                                  ),
                                ).then((_) => _refreshData());
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSortChip(
          label: 'Default',
          icon: Icons.grid_view_rounded,
          isActive: _activeSort == 'default',
          onTap: () {
            setState(() {
              _activeSort = 'default';
              _bloodGroupsOrder = ["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"];
            });
          },
        ),
        const SizedBox(width: 8),
        _buildSortChip(
          label: 'Critical First',
          icon: Icons.warning_amber_rounded,
          isActive: _activeSort == 'bssi',
          onTap: () {
            setState(() {
              _activeSort = 'bssi';
              _applyActiveSort();
            });
          },
        ),
        const SizedBox(width: 8),
        _buildSortChip(
          label: 'Lowest Stock',
          icon: Icons.trending_down_rounded,
          isActive: _activeSort == 'stock',
          onTap: () {
            setState(() {
              _activeSort = 'stock';
              _applyActiveSort();
            });
          },
        ),
      ],
    );
  }

  Widget _buildSortChip({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFF3B30) : const Color(0xFF1B1A22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? const Color(0xFFFF3B30) : Colors.white.withOpacity(0.08),
          width: 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: const Color(0xFFFF3B30).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 14, color: isActive ? Colors.white : Colors.grey),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.white : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards(double totalUnits, int criticalCount) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 620;
        final cardWidth = isNarrow 
            ? (constraints.maxWidth - 12) / 2 
            : (constraints.maxWidth - 32) / 3;
        
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSummaryCard(
              title: 'Total Stock',
              value: '${totalUnits.toStringAsFixed(1)} Units',
              icon: Icons.water_drop_rounded,
              color: const Color(0xFFFF3B30),
              width: cardWidth,
            ),
            _buildSummaryCard(
              title: 'Critical Shortages',
              value: criticalCount == 0 ? 'No Shortages' : '$criticalCount Groups',
              icon: Icons.notification_important_rounded,
              color: criticalCount == 0 ? const Color(0xFF30D158) : const Color(0xFFFF9F0A),
              width: cardWidth,
            ),
            if (!isNarrow)
              _buildSummaryCard(
                title: 'Operational Status',
                value: 'Fully Synced',
                icon: Icons.cloud_done_rounded,
                color: Colors.blueAccent,
                width: cardWidth,
              ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  // --- TAB 2: REDISTRIBUTION SUGGESTIONS ---
  Widget _buildRedistributionsTab(AppState state) {
    // Collect all blood groups with BSSI > 75 to display inter-bank suggetions
    final criticalGroups = _bssiScores.entries
        .where((entry) => entry.value > 75.0)
        .map((entry) => entry.key)
        .toList();

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Inter-Bank Redistribution Proposals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Automatically appears for blood groups with BSSI > 75 (Critical / Emergency)',
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
          ),
          const SizedBox(height: 16),
          
          Expanded(
            child: criticalGroups.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 64, color: Color(0xFF30D158)),
                        const SizedBox(height: 16),
                        Text(
                          'All blood groups are in safe stock ranges.',
                          style: TextStyle(color: Colors.white.withOpacity(0.5)),
                        ),
                        const SizedBox(height: 4),
                        const Text('No redistributions required.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: criticalGroups.length,
                    itemBuilder: (context, index) {
                      final bg = criticalGroups[index];
                      return RedistributionSuggestionCard(
                        bankId: state.bankId!,
                        bloodGroup: bg,
                        backendUrl: state.backendUrl,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // --- TAB 3: ALERT HISTORY ---
  Widget _buildAlertHistoryTab(AppState state) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Shortage Alert History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          
          Expanded(
            child: _alertHistory.isEmpty
                ? Center(
                    child: Text(
                      'No shortage alerts triggered in the last 30 days.',
                      style: TextStyle(color: Colors.white.withOpacity(0.3)),
                    ),
                  )
                : ListView.builder(
                    itemCount: _alertHistory.length,
                    itemBuilder: (context, index) {
                      final alert = _alertHistory[index];
                      final date = DateTime.parse(alert['triggered_at']);
                      final rate = (alert['response_rate'] * 100).toStringAsFixed(0);
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${alert['blood_group']} Mobilization',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      DateFormat('dd MMM, HH:mm').format(date.toLocal()),
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  )
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildStatColumn('BSSI Trigger', '${alert['bssi_at_trigger']}'),
                                  _buildStatColumn('Notified', '${alert['donors_notified']}'),
                                  _buildStatColumn('Responded', '${alert['donors_responded']}'),
                                  _buildStatColumn('Response Rate', '$rate%'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // --- TAB 4: UPDATE INVENTORY (LOG DONATION/TRANSFUSION) ---
  Widget _buildUpdateInventoryTab(AppState state) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: LogInventoryTransactionForm(bankId: state.bankId!, backendUrl: state.backendUrl, onCompleted: _refreshData),
      ),
    );
  }
}

// --- BLOOD GROUP DETAILS & LINE CHART FORECAST SCREEN ---
class BloodGroupDetailScreen extends StatefulWidget {
  final int bankId;
  final String bloodGroup;
  final double currentStock;
  final double expiringStock;
  final double bssiScore;
  
  const BloodGroupDetailScreen({
    super.key,
    required this.bankId,
    required this.bloodGroup,
    required this.currentStock,
    required this.expiringStock,
    required this.bssiScore,
  });

  @override
  State<BloodGroupDetailScreen> createState() => _BloodGroupDetailScreenState();
}

class _BloodGroupDetailScreenState extends State<BloodGroupDetailScreen> {
  bool _isLoading = true;
  List _forecasts = [];
  Map<String, dynamic> _bssiFactors = {};
  bool _isTriggering = false;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    final state = Provider.of<AppState>(context, listen: false);
    
    try {
      // 1. Fetch Forecast Cache
      final fRes = await http.get(Uri.parse('${state.backendUrl}/forecast/${widget.bankId}/${widget.bloodGroup}'));
      // 2. Fetch BSSI detail
      final bRes = await http.get(Uri.parse('${state.backendUrl}/bssi/${widget.bankId}/${widget.bloodGroup}'));
      
      if (fRes.statusCode == 200 && bRes.statusCode == 200) {
        setState(() {
          _forecasts = jsonDecode(fRes.body);
          _bssiFactors = jsonDecode(bRes.body)['factors'] ?? {};
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      print("Error loading blood group detail: $e");
    }
  }

  Future<void> _triggerDonorAlert() async {
    setState(() => _isTriggering = true);
    
    final state = Provider.of<AppState>(context, listen: false);
    final url = Uri.parse('${state.backendUrl}/alerts/trigger/${widget.bankId}/${widget.bloodGroup}');
    
    try {
      final response = await http.post(url);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        setState(() => _isTriggering = false);
        
        // Show success alert
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF30D158),
            content: Text('Alert triggered! ${data['donors_notified']} eligible donors notified nearby.'),
          ),
        );
        
        // --- SIMULATE LOCAL PUSH NOTIFICATION ON DONOR PROFILE FOR DEMO ---
        // If a real donor is logged in locally, trigger their notification banner
        // We're simulating that the top donor is the logged-in donor
        if (data['notifications'] != null && data['notifications'].isNotEmpty) {
          final notifyList = data['notifications'] as List;
          // Set notification data
          final mockNotif = {
            'log_id': notifyList[0]['log_id'],
            'bank_name': state.name,
            'distance_km': notifyList[0]['distance_km'],
            'eta_minutes': notifyList[0]['eta_minutes'],
            'blood_group': widget.bloodGroup,
            'bssi': widget.bssiScore,
          };
          
          // Inject notification delay
          Future.delayed(const Duration(seconds: 2), () {
            state.triggerMockNotification(mockNotif);
          });
        }
        
      } else {
        setState(() => _isTriggering = false);
      }
    } catch (e) {
      setState(() => _isTriggering = false);
      print("Error triggering alert: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.bloodGroup} Analytics')),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30)))
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Stock and BSSI stats overview
                    Row(
                      children: [
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  const Text('Units Available', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  const SizedBox(height: 8),
                                  Text('${widget.currentStock}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  const Text('BSSI Severity', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${widget.bssiScore.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 24, 
                                      fontWeight: FontWeight.bold,
                                      color: widget.bssiScore > 55 ? const Color(0xFFFF3B30) : const Color(0xFF30D158)
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Forecast line chart card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('7-Day Demand Forecasting (Prophet)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Predicted consumption vs stock safety line', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4))),
                            const SizedBox(height: 24),
                            
                            // LineChart
                            SizedBox(
                              height: 180,
                              child: _forecasts.isEmpty
                                  ? const Center(child: Text('No forecast points cached.'))
                                  : LineChart(
                                      LineChartData(
                                        gridData: FlGridData(show: true, drawVerticalLine: false),
                                        titlesData: FlTitlesData(
                                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
                                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                          bottomTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              getTitlesWidget: (val, meta) {
                                                if (val.toInt() >= 0 && val.toInt() < _forecasts.length) {
                                                  final dt = DateTime.parse(_forecasts[val.toInt()]['date']);
                                                  return Padding(
                                                    padding: const EdgeInsets.only(top: 6.0),
                                                    child: Text(DateFormat('dd').format(dt), style: const TextStyle(fontSize: 10)),
                                                  );
                                                }
                                                return const Text('');
                                              },
                                            ),
                                          ),
                                        ),
                                        borderData: FlBorderData(show: false),
                                        lineBarsData: [
                                          // Projected Demand Line (Red)
                                          LineChartBarData(
                                            spots: List.generate(_forecasts.length, (idx) {
                                              return FlSpot(idx.toDouble(), _forecasts[idx]['yhat']);
                                            }),
                                            isCurved: true,
                                            color: const Color(0xFFFF3B30),
                                            barWidth: 3,
                                            dotData: FlDotData(show: true),
                                          ),
                                          // Safe threshold floor line (dashed Grey)
                                          LineChartBarData(
                                            spots: List.generate(_forecasts.length, (idx) {
                                              return FlSpot(idx.toDouble(), widget.currentStock);
                                            }),
                                            isCurved: false,
                                            color: Colors.grey.withOpacity(0.4),
                                            barWidth: 1.5,
                                            dashArray: [5, 5],
                                            dotData: FlDotData(show: false),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // BSSI factor weights breakdown
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('BSSI Factor Weights Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            _buildFactorProgressBar('Inventory Gap (35%)', _bssiFactors['inventory_gap'] ?? 0.0),
                            const SizedBox(height: 12),
                            _buildFactorProgressBar('Donation Trend (25%)', _bssiFactors['donation_trend'] ?? 0.0),
                            const SizedBox(height: 12),
                            _buildFactorProgressBar('Accident Signal (20%)', _bssiFactors['accident_signal'] ?? 0.0),
                            const SizedBox(height: 12),
                            _buildFactorProgressBar('Rare Group Flag (10%)', _bssiFactors['rare_group'] ?? 0.0),
                            const SizedBox(height: 12),
                            _buildFactorProgressBar('Expiry Pressure (10%)', _bssiFactors['expiry_pressure'] ?? 0.0),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Shortage Timeline & Mobilize Actions
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: widget.bssiScore > 55 ? const Color(0xFFFF3B30).withOpacity(0.1) : Colors.white.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: widget.bssiScore > 55 ? const Color(0xFFFF3B30).withOpacity(0.3) : Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                widget.bssiScore > 55 ? Icons.warning_amber : Icons.check_circle_outline,
                                color: widget.bssiScore > 55 ? const Color(0xFFFF3B30) : const Color(0xFF30D158),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  widget.bssiScore > 75 
                                      ? 'O+ is critical. Forecast predicts depletion in 4 days.'
                                      : 'Stock is adequate to cover next 7 days of predicted demand.',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              )
                            ],
                          ),
                          if (widget.bssiScore > 55) ...[
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _isTriggering ? null : _triggerDonorAlert,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF3B30),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _isTriggering
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text('Trigger Urgent Donor Alert', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildFactorProgressBar(String label, double value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            Text('${(value * 100).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(
              value > 0.6 ? const Color(0xFFFF3B30) : const Color(0xFF30D158)
            ),
          ),
        ),
      ],
    );
  }
}

// --- REDISTRIBUTION SUGGESTION CARD ---
class RedistributionSuggestionCard extends StatefulWidget {
  final int bankId;
  final String bloodGroup;
  final String backendUrl;
  
  const RedistributionSuggestionCard({
    super.key,
    required this.bankId,
    required this.bloodGroup,
    required this.backendUrl,
  });

  @override
  State<RedistributionSuggestionCard> createState() => _RedistributionSuggestionCardState();
}

class _RedistributionSuggestionCardState extends State<RedistributionSuggestionCard> {
  bool _isLoading = true;
  List _suggestions = [];

  @override
  void initState() {
    super.initState();
    _fetchSuggestions();
  }

  Future<void> _fetchSuggestions() async {
    try {
      final response = await http.get(
        Uri.parse('${widget.backendUrl}/redistribution/suggest/${widget.bankId}/${widget.bloodGroup}')
      );
      if (response.statusCode == 200) {
        setState(() {
          _suggestions = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      print("Error fetching redistribution suggestions: $e");
    }
  }

  Future<void> _requestTransfer(Map suggestion) async {
    try {
      final response = await http.post(
        Uri.parse('${widget.backendUrl}/redistribution/request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requesting_bank_id': widget.bankId,
          'supplying_bank_id': suggestion['supplying_bank_id'],
          'blood_group': widget.bloodGroup,
          'suggested_units': suggestion['suggested_units'],
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF30D158),
            content: Text('Redistribution transfer request sent to ${suggestion['supplying_bank_name']}!'),
          ),
        );
        _fetchSuggestions();
      }
    } catch (e) {
      print("Error request transfer: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (_suggestions.isEmpty) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'No nearby blood banks possess surplus of ${widget.bloodGroup} to suggest redistribution.',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text(
            'Suggestions for ${widget.bloodGroup}',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF3B30)),
          ),
        ),
        ..._suggestions.map((s) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(s['supplying_bank_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('${s['distance_km']} km away', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Surplus Stock', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(height: 2),
                          Text('${s['surplus_units']} Units', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Suggested Transfer', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(height: 2),
                          Text(
                            '${s['suggested_units']} Units',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                          ),
                        ],
                      ),
                      ElevatedButton(
                        onPressed: () => _requestTransfer(s),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: const Text('Request'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }
}

// --- UPDATE INVENTORY FORM ---
class LogInventoryTransactionForm extends StatefulWidget {
  final int bankId;
  final String backendUrl;
  final VoidCallback onCompleted;
  
  const LogInventoryTransactionForm({
    super.key,
    required this.bankId,
    required this.backendUrl,
    required this.onCompleted,
  });

  @override
  State<LogInventoryTransactionForm> createState() => _LogInventoryTransactionFormState();
}

class _LogInventoryTransactionFormState extends State<LogInventoryTransactionForm> {
  final _unitsController = TextEditingController();
  final _donorController = TextEditingController();
  final _hospitalController = TextEditingController();
  
  String _selectedBloodGroup = 'O+';
  String _transactionType = 'donation'; // 'donation' (inflow), 'transfusion' (outflow)
  bool _emergencyFlag = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _unitsController.dispose();
    _donorController.dispose();
    _hospitalController.dispose();
    super.dispose();
  }

  Future<void> _submitTransaction() async {
    final units = double.tryParse(_unitsController.text);
    if (units == null || units <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid number of units.')),
      );
      return;
    }
    
    setState(() => _isSaving = true);
    
    final payload = {
      'bank_id': widget.bankId,
      'blood_group': _selectedBloodGroup,
      'transaction_type': _transactionType,
      'units': units,
      'donor_id': _transactionType == 'donation' && _donorController.text.isNotEmpty 
          ? int.tryParse(_donorController.text) 
          : null,
      'hospital_id': _transactionType == 'transfusion' && _hospitalController.text.isNotEmpty 
          ? int.tryParse(_hospitalController.text) 
          : null,
      'emergency_flag': _emergencyFlag,
    };

    try {
      final response = await http.post(
        Uri.parse('${widget.backendUrl}/inventory/update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      setState(() => _isSaving = false);
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Color(0xFF30D158), content: Text('Inventory record logged successfully!')),
        );
        _unitsController.clear();
        _donorController.clear();
        _hospitalController.clear();
        widget.onCompleted();
      } else {
        final err = jsonDecode(response.body)['detail'] ?? 'Could not log record';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    } catch (e) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error connecting to backend: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Log Donation or Transfusion', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        
        // Transaction Type Segmented Toggle
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _transactionType = 'donation'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _transactionType == 'donation' ? const Color(0xFFFF3B30) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Text('Inflow (Donation Received)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _transactionType = 'transfusion'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _transactionType == 'transfusion' ? const Color(0xFFFF3B30) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Text('Outflow (Transfusion Out)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Blood Group Select
        DropdownButtonFormField<String>(
          value: _selectedBloodGroup,
          decoration: InputDecoration(
            labelText: 'Blood Group',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: const Color(0xFF1B1A22),
          ),
          items: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
              .map((g) => DropdownMenuItem(value: g, child: Text(g)))
              .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedBloodGroup = val);
          },
        ),
        const SizedBox(height: 16),

        // Units input
        TextField(
          controller: _unitsController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Units Volume (e.g. 1.0, 5.0)',
            prefixIcon: const Icon(Icons.water_drop_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: const Color(0xFF1B1A22),
          ),
        ),
        const SizedBox(height: 16),

        if (_transactionType == 'donation') ...[
          TextField(
            controller: _donorController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Donor ID (Optional)',
              prefixIcon: const Icon(Icons.person_pin_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: const Color(0xFF1B1A22),
            ),
          ),
        ] else ...[
          TextField(
            controller: _hospitalController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Hospital ID (Optional, defaults to 1)',
              prefixIcon: const Icon(Icons.local_hospital_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: const Color(0xFF1B1A22),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Emergency Flag'),
            subtitle: const Text('Check if this is an urgent/critical demand out'),
            value: _emergencyFlag,
            activeColor: const Color(0xFFFF3B30),
            onChanged: (val) => setState(() => _emergencyFlag = val),
          ),
        ],
        
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: _isSaving ? null : _submitTransaction,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF3B30),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isSaving
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Log Transaction', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class HoverableBloodGroupCard extends StatefulWidget {
  final String bloodGroup;
  final Map<String, dynamic> stock;
  final double bssi;
  final Color cellColor;
  final VoidCallback onTap;
  final int index;

  const HoverableBloodGroupCard({
    super.key,
    required this.bloodGroup,
    required this.stock,
    required this.bssi,
    required this.cellColor,
    required this.onTap,
    required this.index,
  });

  @override
  State<HoverableBloodGroupCard> createState() => _HoverableBloodGroupCardState();
}

class _HoverableBloodGroupCardState extends State<HoverableBloodGroupCard> {
  bool _isHovered = false;
  double _opacity = 0.0;
  double _offsetY = 30.0;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.index * 60), () {
      if (mounted) {
        setState(() {
          _opacity = 1.0;
          _offsetY = 0.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cellColor = widget.cellColor;
    final stock = widget.stock;
    final bssi = widget.bssi;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 200),
        tween: Tween(begin: 0.0, end: _isHovered ? 1.0 : 0.0),
        builder: (context, hoverProgress, child) {
          final scale = 1.0 + (hoverProgress * 0.04);
          final glowOpacity = 0.4 + (hoverProgress * 0.4);
          final shadowSpread = hoverProgress * 8.0;

          return TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 400),
            tween: Tween(begin: 30.0, end: _offsetY),
            curve: Curves.easeOutBack,
            builder: (context, offset, child) {
              return AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _opacity,
                child: Transform.translate(
                  offset: Offset(0, offset),
                  child: Transform.scale(
                    scale: scale,
                    child: child,
                  ),
                ),
              );
            },
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF1B1A22),
                      Color.lerp(const Color(0xFF1B1A22), cellColor, 0.05)!,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cellColor.withOpacity(glowOpacity),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: cellColor.withOpacity(0.15 * hoverProgress),
                      blurRadius: 12 + shadowSpread,
                      spreadRadius: 1 + (hoverProgress * 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.bloodGroup,
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                            if (bssi > 75) ...[
                              const SizedBox(width: 8),
                              _PulseWarningDot(color: cellColor),
                            ],
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: cellColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cellColor.withOpacity(0.3), width: 1),
                          ),
                          child: Text(
                            'BSSI ${bssi.toStringAsFixed(0)}',
                            style: TextStyle(color: cellColor, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          if (_isHovered)
                            Shadow(
                              color: Colors.white.withOpacity(0.3),
                              blurRadius: 4,
                            ),
                        ],
                      ),
                      child: Text('${stock['units_available']} Units'),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: stock['units_expiring_3days'] > 0 ? const Color(0xFFFF9F0A) : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Expiring (3d): ${stock['units_expiring_3days']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: stock['units_expiring_3days'] > 0 ? const Color(0xFFFF9F0A) : Colors.grey,
                            fontWeight: stock['units_expiring_3days'] > 0 ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PulseWarningDot extends StatefulWidget {
  final Color color;
  const _PulseWarningDot({required this.color});

  @override
  State<_PulseWarningDot> createState() => _PulseWarningDotState();
}

class _PulseWarningDotState extends State<_PulseWarningDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.5 * _controller.value),
                blurRadius: 6 * _controller.value,
                spreadRadius: 2 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
}


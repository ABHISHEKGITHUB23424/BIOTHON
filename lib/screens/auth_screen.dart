import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../main.dart';
import '../utils/file_picker_helper.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Navigation states
  // 0 = Landing Dashboard with Mission Statement and Portal Selectors
  // 1 = Donor Portal (Login / Register Toggle)
  // 2 = Admin Portal (Login)
  // 3 = Donor Registration Form
  int _currentView = 0;
  
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  
  bool _isRegistering = false; // Toggle between Login and Register inside Donor portal
  bool _isVerifying = false;
  String? _errorMessage;
  
  // Registration Form Controllers
  final _regNameController = TextEditingController();
  final _regPhoneController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regCityController = TextEditingController(text: 'Delhi NCR');
  String _regSelectedBloodGroup = 'O+';
  String _regSelectedCity = 'Delhi NCR';
  DateTime _regSelectedDob = DateTime.now().subtract(const Duration(days: 22 * 365));
  bool _regLocationPermission = true;
  PickedFile? _selectedIdDocument;
  bool _regConsentGiven = false;

  // Admin Registration Form Controllers
  final _adminRegNameController = TextEditingController();
  final _adminRegPhoneController = TextEditingController();
  final _adminRegPasswordController = TextEditingController();
  final _adminRegAddressController = TextEditingController();
  final _adminRegWebsiteController = TextEditingController();
  
  String _adminRegSelectedRegion = 'Delhi NCR';
  DateTime _adminRegSelectedEstDate = DateTime.now().subtract(const Duration(days: 10 * 365));
  PickedFile? _adminRegSelectedDoc;
  PickedFile? _adminRegSelectedDatabaseFile;
  bool _adminRegConsentGiven = false;

  int _calculateAge(DateTime birthDate) {
    DateTime today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _regNameController.dispose();
    _regPhoneController.dispose();
    _regPasswordController.dispose();
    _regCityController.dispose();
    _adminRegNameController.dispose();
    _adminRegPhoneController.dispose();
    _adminRegPasswordController.dispose();
    _adminRegAddressController.dispose();
    _adminRegWebsiteController.dispose();
    super.dispose();
  }

  String _parseErrorDetail(dynamic detail, {String fallback = 'An error occurred'}) {
    if (detail == null) return fallback;
    if (detail is String) return detail;
    if (detail is List) {
      try {
        return detail.map((e) {
          if (e is Map && e.containsKey('msg')) {
            final loc = e['loc'] is List ? (e['loc'] as List).join('.') : '';
            final msg = e['msg'] ?? '';
            return loc.isNotEmpty ? '$loc: $msg' : '$msg';
          }
          return e.toString();
        }).join(', ');
      } catch (_) {
        return detail.toString();
      }
    }
    return detail.toString();
  }

  Future<void> _handleLogin(String phone, String password, String role) async {
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final state = Provider.of<AppState>(context, listen: false);
    final url = Uri.parse('${state.backendUrl}/auth/login');
    
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'password': password,
          'role': role,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final uid = data['profile']['firebase_uid'];
        final role = data['role'];
        final profile = data['profile'];
        final token = data['token'] ?? '';
        await state.login(role, uid, profile, token: token);
      } else {
        final errorData = jsonDecode(response.body);
        setState(() {
          _errorMessage = _parseErrorDetail(errorData['detail'], fallback: 'Login failed. Please check credentials.');
          _isVerifying = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Cannot connect to server: $e';
        _isVerifying = false;
      });
    }
  }

  Future<void> _handleRegister() async {
    if (_regNameController.text.isEmpty || _regPhoneController.text.isEmpty || _regPasswordController.text.isEmpty) {
      setState(() => _errorMessage = "Please fill in all details.");
      return;
    }

    final phoneRegex = RegExp(r"^\+91[6-9]\d{9}$");
    if (!phoneRegex.hasMatch(_regPhoneController.text)) {
      setState(() => _errorMessage = "Mobile number must be in format +91 followed by 10 digits starting with 6-9.");
      return;
    }

    final passwordRegex = RegExp(r"^(?=.*[0-9]).{8,}$");
    if (!passwordRegex.hasMatch(_regPasswordController.text)) {
      setState(() => _errorMessage = "Password must be at least 8 characters long and contain at least one digit.");
      return;
    }

    final age = _calculateAge(_regSelectedDob);
    if (age < 18) {
      setState(() => _errorMessage = "You must be 18 years or older to register.");
      return;
    }

    if (_selectedIdDocument == null) {
      setState(() => _errorMessage = "Identity verification document is required.");
      return;
    }

    if (!_regConsentGiven) {
      setState(() => _errorMessage = "You must give consent under DPDP Act 2023 to register.");
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final state = Provider.of<AppState>(context, listen: false);
    final registerUrl = Uri.parse('${state.backendUrl}/donors/register');
    final setupUrl = Uri.parse('${state.backendUrl}/auth/profile-setup');
    
    final uid = "firebase_uid_${_regPhoneController.text.replaceAll('+', '').trim()}";

    // Map selected city/region to standard coordinate centers
    double lat = 28.6139;
    double lng = 77.2090;
    if (_regSelectedCity == 'Mumbai MMR') {
      lat = 19.0760;
      lng = 72.8777;
    } else if (_regSelectedCity == 'Bengaluru Urban') {
      lat = 12.9716;
      lng = 77.5946;
    } else if (_regSelectedCity == 'Chennai') {
      lat = 13.0827;
      lng = 80.2707;
    }

    // Add randomized jitter to coordinates so donors are scattered realistically
    final seconds = DateTime.now().second;
    lat += (0.015 * ((seconds % 4) - 2));
    lng += (0.015 * ((seconds % 3) - 1));

    try {
      // 1. Register donor in DB
      final regRes = await http.post(
        registerUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'firebase_uid': uid,
          'name': _regNameController.text,
          'phone': _regPhoneController.text,
          'blood_group': _regSelectedBloodGroup,
          'dob': _regSelectedDob.toIso8601String().split('T')[0],
          'location_lat': lat,
          'location_lng': lng,
          'password': _regPasswordController.text,
          'consent_given': _regConsentGiven,
          'id_document_base64': _selectedIdDocument?.base64Content,
          'id_document_name': _selectedIdDocument?.name,
          'fcm_token': 'fcm_token_${_regPhoneController.text.replaceAll('replaceAll', '').trim()}',
        }),
      );

      if (regRes.statusCode == 200) {
        final regData = jsonDecode(regRes.body);
        final donorId = regData['donor_id'];
        final token = regData['token'] ?? '';

        // 2. Set up Auth Profile mapping
        final setupRes = await http.post(
          setupUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'firebase_uid': uid,
            'role': 'donor',
            'name': _regNameController.text,
            'blood_group': _regSelectedBloodGroup,
            'dob': _regSelectedDob.toIso8601String().split('T')[0],
            'city': _regSelectedCity,
            'phone': _regPhoneController.text,
          }),
        );

        if (setupRes.statusCode == 200) {
          final profile = {
            'name': _regNameController.text,
            'blood_group': _regSelectedBloodGroup,
            'phone': _regPhoneController.text,
            'city': _regSelectedCity,
            'donor_id': donorId,
          };
          await state.login('donor', uid, profile, token: token);
        } else {
          setState(() {
            _errorMessage = 'Profile mapping failed.';
            _isVerifying = false;
          });
        }
      } else {
        final errorData = jsonDecode(regRes.body);
        setState(() {
          _errorMessage = _parseErrorDetail(errorData['detail'], fallback: 'Registration failed. Phone number might be registered.');
          _isVerifying = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error establishing connection: $e';
        _isVerifying = false;
      });
    }
  }

  void _showBackendSettings() {
    final state = Provider.of<AppState>(context, listen: false);
    final controller = TextEditingController(text: state.backendUrl);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server Configuration'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'FastAPI Backend URL',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              state.setBackendUrl(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLOODSENSE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey),
            onPressed: _showBackendSettings,
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                if (_currentView == 0) ..._buildLandingView(),
                if (_currentView == 1) ..._buildDonorPortal(),
                if (_currentView == 2) ..._buildAdminPortal(),
                if (_currentView == 3) ..._buildDonorRegistrationForm(),
                if (_currentView == 4) ..._buildAdminRegistrationForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- VIEW 0: LANDING DASHBOARD ---
  List<Widget> _buildLandingView() {
    return [
      const SizedBox(height: 16),
      Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFF3B30).withOpacity(0.1),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF3B30).withOpacity(0.2),
                blurRadius: 24,
                spreadRadius: 2,
              )
            ],
          ),
          child: const Icon(Icons.favorite, size: 76, color: Color(0xFFFF3B30)),
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Predict. Alert. Save.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
      const SizedBox(height: 8),
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF30D158).withOpacity(0.15),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.online_prediction, color: Color(0xFF30D158), size: 14),
              SizedBox(width: 4),
              Text(
                'AI FORECASTING ONLINE',
                style: TextStyle(color: Color(0xFF30D158), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      
      // Glassmorphic Mission Narrative Box
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white.withOpacity(0.04), Colors.white.withOpacity(0.01)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology, color: Color(0xFFFF3B30), size: 18),
                const SizedBox(width: 8),
                const Text(
                  'SYSTEM MISSION STATEMENT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFF3B30),
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'BloodSense utilizes advanced time-series forecasting (FB Prophet) to predict blood shortages 3–7 days in advance. '
              'By calculating a composite Blood Shortage Severity Index (BSSI) every 6 hours, '
              'the platform replaces chaotic emergency panic with proactive regional donor mobilization—routing nearby '
              'eligible donors directly to blood banks facing critical inventory deficits.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.65),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 32),
      
      const Text(
        'CHOOSE SYSTEM PORTAL',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 16),

      // Card Portal 1: Donor
      _buildPortalSelectorCard(
        title: 'Blood Donor Portal',
        subtitle: 'Donate blood, check local shortage caution index, and respond to alerts.',
        icon: Icons.biotech,
        gradientColors: [const Color(0xFFFF3B30).withOpacity(0.12), const Color(0xFF1B1A22)],
        borderColor: const Color(0xFFFF3B30).withOpacity(0.25),
        onTap: () {
          setState(() {
            _currentView = 1;
            _isRegistering = false;
          });
        },
      ),
      const SizedBox(height: 16),

      // Card Portal 2: Admin
      _buildPortalSelectorCard(
        title: 'Blood Bank Administration',
        subtitle: 'Manage inventory, audit Prophet prediction charts, and dispatch donor mobilization alerts.',
        icon: Icons.domain,
        gradientColors: [Colors.blue.withOpacity(0.12), const Color(0xFF1B1A22)],
        borderColor: Colors.blue.withOpacity(0.25),
        onTap: () {
          setState(() {
            _currentView = 2;
          });
        },
      ),
      const SizedBox(height: 20),
      
      // Coordinator Quick Selector
      Center(
        child: TextButton.icon(
          onPressed: () {
            final state = Provider.of<AppState>(context, listen: false);
            state.login('coordinator', 'mock_uid_coordinator', {'name': 'Health Coordinator', 'city': 'Delhi NCR'});
          },
          icon: const Icon(Icons.health_and_safety_outlined, size: 16, color: Colors.grey),
          label: const Text('Enter as Emergency Coordinator (Heatmap)', style: TextStyle(color: Colors.grey, fontSize: 13)),
        ),
      ),
    ];
  }

  Widget _buildPortalSelectorCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradientColors,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4))),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
          ],
        ),
      ),
    );
  }

  // --- VIEW 1: DONOR PORTAL (LOGIN / REGISTER CHANGER) ---
  List<Widget> _buildDonorPortal() {
    return [
      Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _currentView = 0),
          ),
          const Text('Back to portals'),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'Blood Donor Sign In',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(
        'Receive critical local shortage notifications based on your blood group.',
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
      ),
      const SizedBox(height: 32),
      
      TextField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: 'Registered Phone Number',
          prefixIcon: const Icon(Icons.phone_iphone),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _passwordController,
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'Password',
          prefixIcon: const Icon(Icons.lock_outline),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
      ),
      const SizedBox(height: 24),
      
      ElevatedButton(
        onPressed: _isVerifying 
            ? null 
            : () => _handleLogin(_phoneController.text, _passwordController.text, 'donor'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF3B30),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isVerifying
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Login as Donor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      const SizedBox(height: 24),
      
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('New donor? '),
          TextButton(
            onPressed: () {
              setState(() {
                _currentView = 3; // Onboarding Register Form
              });
            },
            child: const Text('Register New Account', style: TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ];
  }

  // --- VIEW 2: ADMIN PORTAL ---
  List<Widget> _buildAdminPortal() {
    return [
      Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _currentView = 0),
          ),
          const Text('Back to portals'),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'Blood Bank Manager Login',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(
        'Access inventory dashboards, Prophet forecasting reports, and donor nudges.',
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
      ),
      const SizedBox(height: 32),
      
      TextField(
        controller: _phoneController,
        decoration: InputDecoration(
          labelText: 'Admin Username / Phone',
          prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _passwordController,
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'Password',
          prefixIcon: const Icon(Icons.lock_outline),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
      ),
      const SizedBox(height: 24),
      
      ElevatedButton(
        onPressed: _isVerifying 
            ? null 
            : () => _handleLogin(_phoneController.text, _passwordController.text, 'bank_admin'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isVerifying
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Login as Admin', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      const SizedBox(height: 16),
      Center(
        child: Text(
          'Demo Admin ID: admin | Password: admin123',
          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.3)),
        ),
      ),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('New blood bank? '),
          TextButton(
            onPressed: () {
              setState(() {
                _currentView = 4;
                _errorMessage = null;
              });
            },
            child: const Text('Register Blood Bank', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ];
  }

  // --- VIEW 3: DONOR REGISTRATION FORM ---
  List<Widget> _buildDonorRegistrationForm() {
    return [
      Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _currentView = 1),
          ),
          const Text('Back to Donor Login'),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'Create Donor Account',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(
        'Enter details to register and verify nearby blood shortages.',
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
      ),
      const SizedBox(height: 24),
      
      // Personal details
      TextField(
        controller: _regNameController,
        decoration: InputDecoration(
          labelText: 'Full Name',
          prefixIcon: const Icon(Icons.person_outline),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _regPhoneController,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: 'Mobile Number',
          prefixIcon: const Icon(Icons.phone_iphone),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _regPasswordController,
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'Create Password',
          prefixIcon: const Icon(Icons.lock_outline),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
      ),
      const SizedBox(height: 12),
      
      // Blood Group Select
      DropdownButtonFormField<String>(
        value: _regSelectedBloodGroup,
        decoration: InputDecoration(
          labelText: 'Blood Group',
          prefixIcon: const Icon(Icons.bloodtype_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
        items: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
            .map((g) => DropdownMenuItem(value: g, child: Text(g)))
            .toList(),
        onChanged: (val) {
          if (val != null) setState(() => _regSelectedBloodGroup = val);
        },
      ),
      const SizedBox(height: 12),

      // Area/City Dropdown
      DropdownButtonFormField<String>(
        value: _regSelectedCity,
        decoration: InputDecoration(
          labelText: 'Area / Region',
          prefixIcon: const Icon(Icons.location_city_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
        items: ['Delhi NCR', 'Mumbai MMR', 'Bengaluru Urban', 'Chennai']
            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
            .toList(),
        onChanged: (val) {
          if (val != null) {
            setState(() {
              _regSelectedCity = val;
              _regCityController.text = val;
            });
          }
        },
      ),
      const SizedBox(height: 12),
      
    // Date of Birth DatePicker
    GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _regSelectedDob,
          firstDate: DateTime(1960),
          lastDate: DateTime.now().subtract(const Duration(days: 18 * 365)),
        );
        if (date != null) setState(() => _regSelectedDob = date);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1A22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month, color: Colors.grey),
                const SizedBox(width: 12),
                Text(
                  'Date of Birth: ${_regSelectedDob.toLocal().toIso8601String().split('T')[0]}',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const Icon(Icons.arrow_drop_down, color: Color(0xFFFF3B30)),
          ],
        ),
      ),
    ),
    const SizedBox(height: 8),

    // Display dynamically calculated Age
    Builder(
      builder: (context) {
        int calculatedAge = _calculateAge(_regSelectedDob);
        bool isEligible = calculatedAge >= 18;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
          child: Row(
            children: [
              Icon(
                isEligible ? Icons.check_circle : Icons.error,
                color: isEligible ? const Color(0xFF30D158) : const Color(0xFFFF3B30),
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Age: $calculatedAge Years ${isEligible ? "(Eligible)" : "(Underage - Blocked)"}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isEligible ? const Color(0xFF30D158) : const Color(0xFFFF3B30),
                ),
              ),
            ],
          ),
        );
      }
    ),
    const SizedBox(height: 12),

    // ID Document Upload Dropzone Card
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _selectedIdDocument != null ? const Color(0xFF30D158).withOpacity(0.5) : Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                color: _selectedIdDocument != null ? const Color(0xFF30D158) : Colors.grey,
              ),
              const SizedBox(width: 12),
              const Text(
                'Upload Identity Document',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Aadhaar Card, Driving License, or Passport (Required)',
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
          ),
          const SizedBox(height: 12),
          if (_selectedIdDocument != null) ...[
            Row(
              children: [
                const Icon(Icons.insert_drive_file, color: Color(0xFF30D158), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final name = _selectedIdDocument!.name;
                      final maskedName = name.length > 4 
                          ? '***${name.substring(name.length - 4)}' 
                          : name;
                      return Text(
                        maskedName,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF30D158), overflow: TextOverflow.ellipsis),
                      );
                    }
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedIdDocument = null),
                  child: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 13)),
                ),
              ],
            ),
          ] else ...[
            OutlinedButton(
              onPressed: () async {
                final file = await FilePickerHelper.pickFile();
                if (file != null) {
                  setState(() {
                    _selectedIdDocument = file;
                    _errorMessage = null;
                  });
                }
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFF3B30)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                'Choose File',
                style: TextStyle(color: Color(0xFFFF3B30), fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    ),
    const SizedBox(height: 12),
    
    // Location permission toggle
    SwitchListTile(
      title: const Text('GPS Proximity Access'),
      subtitle: const Text('Required to match nearest blood bank shortages'),
      value: _regLocationPermission,
      activeColor: const Color(0xFFFF3B30),
      onChanged: (val) => setState(() => _regLocationPermission = val),
    ),
    const SizedBox(height: 12),

    // DPDP Act 2023 Consent Checkbox
    CheckboxListTile(
      title: const Text(
        'DPDP Act 2023 Compliance Consent',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      subtitle: const Text(
        'I consent to securely uploading my identity document (Aadhaar/License) for verification. '
        'My sensitive data will be encrypted and stored in compliance with the DPDP Act 2023.',
        style: TextStyle(fontSize: 11, color: Colors.grey),
      ),
      value: _regConsentGiven,
      activeColor: const Color(0xFFFF3B30),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (val) => setState(() => _regConsentGiven = val ?? false),
    ),
    const SizedBox(height: 24),
      
      ElevatedButton(
        onPressed: _isVerifying ? null : _handleRegister,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF3B30),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isVerifying
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Complete Registration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    ];
  }

  // --- VIEW 4: ADMIN (BLOOD BANK) REGISTRATION FORM ---
  List<Widget> _buildAdminRegistrationForm() {
    return [
      Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _currentView = 2),
          ),
          const Text('Back to Admin Login'),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'Register Blood Bank',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(
        'Onboard your blood bank and upload inventory databases to start Prophet ML calculations.',
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
      ),
      const SizedBox(height: 24),
      
      TextField(
        controller: _adminRegNameController,
        decoration: InputDecoration(
          labelText: 'Blood Bank Official Name',
          prefixIcon: const Icon(Icons.domain_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _adminRegPhoneController,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: 'Official Contact Mobile / Username',
          prefixIcon: const Icon(Icons.phone_iphone),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _adminRegPasswordController,
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'Create Password',
          prefixIcon: const Icon(Icons.lock_outline),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _adminRegAddressController,
        decoration: InputDecoration(
          labelText: 'Complete Postal Address',
          prefixIcon: const Icon(Icons.map_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _adminRegWebsiteController,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: 'Official Website Link (e.g. https://...)',
          prefixIcon: const Icon(Icons.language_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
      ),
      const SizedBox(height: 12),
      
      DropdownButtonFormField<String>(
        value: _adminRegSelectedRegion,
        decoration: InputDecoration(
          labelText: 'Operating Region',
          prefixIcon: const Icon(Icons.location_city_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF1B1A22),
        ),
        items: ['Delhi NCR', 'Mumbai MMR', 'Bengaluru Urban', 'Chennai']
            .map((r) => DropdownMenuItem(value: r, child: Text(r)))
            .toList(),
        onChanged: (val) {
          if (val != null) setState(() => _adminRegSelectedRegion = val);
        },
      ),
      const SizedBox(height: 12),
      
      // Date Picker for Establishment Date
      GestureDetector(
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: _adminRegSelectedEstDate,
            firstDate: DateTime(1900),
            lastDate: DateTime.now(),
          );
          if (date != null) setState(() => _adminRegSelectedEstDate = date);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1A22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_month, color: Colors.grey),
                  const SizedBox(width: 12),
                  Text(
                    'Established Date: ${_adminRegSelectedEstDate.toLocal().toIso8601String().split('T')[0]}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.blueAccent),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),

      // Official Approval/License Document Upload Card
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1A22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _adminRegSelectedDoc != null ? const Color(0xFF30D158).withOpacity(0.5) : Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: _adminRegSelectedDoc != null ? const Color(0xFF30D158) : Colors.grey,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Upload Licensing Document',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Govt Blood Bank License or NABL Approval PDF/Image (Required)',
              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
            ),
            const SizedBox(height: 12),
            if (_adminRegSelectedDoc != null) ...[
              Row(
                children: [
                  const Icon(Icons.insert_drive_file, color: Color(0xFF30D158), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _adminRegSelectedDoc!.name,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF30D158), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _adminRegSelectedDoc = null),
                    child: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                ],
              ),
            ] else ...[
              OutlinedButton(
                onPressed: () async {
                  final file = await FilePickerHelper.pickFile();
                  if (file != null) {
                    setState(() {
                      _adminRegSelectedDoc = file;
                      _errorMessage = null;
                    });
                  }
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.blueAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'Choose License File',
                  style: TextStyle(color: Colors.blueAccent, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),

      // Past database and Inventory uploader card
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1A22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _adminRegSelectedDatabaseFile != null ? const Color(0xFF30D158).withOpacity(0.5) : Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.storage_rounded,
                  color: _adminRegSelectedDatabaseFile != null ? const Color(0xFF30D158) : Colors.grey,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Upload Donations & Inventory DB',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Upload CSV or JSON of past 1 year donations, transfusions, and current stocks (Required)',
              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
            ),
            const SizedBox(height: 12),
            if (_adminRegSelectedDatabaseFile != null) ...[
              Row(
                children: [
                  const Icon(Icons.analytics_outlined, color: Color(0xFF30D158), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _adminRegSelectedDatabaseFile!.name,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF30D158), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _adminRegSelectedDatabaseFile = null),
                    child: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                ],
              ),
            ] else ...[
              OutlinedButton(
                onPressed: () async {
                  final file = await FilePickerHelper.pickFile();
                  if (file != null) {
                    setState(() {
                      _adminRegSelectedDatabaseFile = file;
                      _errorMessage = null;
                    });
                  }
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.blueAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'Choose Database File',
                  style: TextStyle(color: Colors.blueAccent, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),

      // DPDP Act 2023 Consent Checkbox
      CheckboxListTile(
        title: const Text(
          'DPDP Act 2023 Consent & Compliance',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'We consent to securely upload our blood bank license and inventory data. '
          'Our database information will be stored securely and encrypted in compliance with the DPDP Act 2023.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        value: _adminRegConsentGiven,
        activeColor: Colors.blueAccent,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (val) => setState(() => _adminRegConsentGiven = val ?? false),
      ),
      const SizedBox(height: 24),
      
      ElevatedButton(
        onPressed: _isVerifying ? null : _handleAdminRegister,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isVerifying
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Complete Blood Bank Setup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    ];
  }

  Future<void> _handleAdminRegister() async {
    if (_adminRegNameController.text.isEmpty ||
        _adminRegPhoneController.text.isEmpty ||
        _adminRegPasswordController.text.isEmpty ||
        _adminRegAddressController.text.isEmpty) {
      setState(() => _errorMessage = "Please fill in all details.");
      return;
    }

    final phoneRegex = RegExp(r"^\+91[6-9]\d{9}$");
    if (!phoneRegex.hasMatch(_adminRegPhoneController.text)) {
      setState(() => _errorMessage = "Phone number must be in format +91 followed by 10 digits starting with 6-9.");
      return;
    }

    final passwordRegex = RegExp(r"^(?=.*[0-9]).{8,}$");
    if (!passwordRegex.hasMatch(_adminRegPasswordController.text)) {
      setState(() => _errorMessage = "Password must be at least 8 characters long and contain at least one digit.");
      return;
    }

    if (_adminRegSelectedDoc == null) {
      setState(() => _errorMessage = "Approval verification document is required.");
      return;
    }

    if (_adminRegSelectedDatabaseFile == null) {
      setState(() => _errorMessage = "Historical database and inventory file upload is required.");
      return;
    }

    if (!_adminRegConsentGiven) {
      setState(() => _errorMessage = "You must give consent under DPDP Act 2023 to register.");
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final state = Provider.of<AppState>(context, listen: false);
    final registerUrl = Uri.parse('${state.backendUrl}/banks/register');

    int regionId = 1;
    double lat = 28.6139;
    double lng = 77.2090;

    if (_adminRegSelectedRegion == 'Mumbai MMR') {
      regionId = 2;
      lat = 19.0760;
      lng = 72.8777;
    } else if (_adminRegSelectedRegion == 'Bengaluru Urban') {
      regionId = 3;
      lat = 12.9716;
      lng = 77.5946;
    } else if (_adminRegSelectedRegion == 'Chennai') {
      regionId = 4;
      lat = 13.0827;
      lng = 80.2707;
    }

    final seconds = DateTime.now().second;
    lat += (0.012 * ((seconds % 4) - 2));
    lng += (0.012 * ((seconds % 3) - 1));

    // Generate mock inventory data (8 standard groups)
    final List<Map<String, dynamic>> inventoryData = [
      {'blood_group': 'O+', 'units': 12.5 + _randomJitter(5.0)},
      {'blood_group': 'O-', 'units': 4.0 + _randomJitter(3.0)},
      {'blood_group': 'A+', 'units': 15.0 + _randomJitter(5.0)},
      {'blood_group': 'A-', 'units': 4.5 + _randomJitter(3.0)},
      {'blood_group': 'B+', 'units': 14.0 + _randomJitter(5.0)},
      {'blood_group': 'B-', 'units': 6.0 + _randomJitter(3.0)},
      {'blood_group': 'AB+', 'units': 8.0 + _randomJitter(4.0)},
      {'blood_group': 'AB-', 'units': 2.0 + _randomJitter(2.0)},
    ];

    // Generate mock historical data (300 days of daily records)
    final List<Map<String, dynamic>> donations = [];
    final List<Map<String, dynamic>> transfusions = [];
    final today = DateTime.now();

    final bloodGroups = ["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"];

    for (int i = 300; i >= 1; i--) {
      final date = today.subtract(Duration(days: i));
      final dateStr = date.toIso8601String().split('T')[0];

      for (final bg in bloodGroups) {
        final isCriticalGroup = (bg == 'O+' || bg == 'O-');
        
        double donUnits = (seconds % 3 == 0) ? (1.0 + (seconds % 3)) : 0.0;
        if (donUnits > 0) {
          donations.add({
            'date': dateStr,
            'blood_group': bg,
            'units': donUnits,
          });
        }

        double transUnits = 0.0;
        if (isCriticalGroup) {
          transUnits = (seconds % 4 == 0) ? (2.0 + (seconds % 4)) : 1.0;
        } else {
          transUnits = (seconds % 5 == 0) ? (1.0 + (seconds % 2)) : 0.0;
        }

        if (transUnits > 0) {
          transfusions.add({
            'date': dateStr,
            'blood_group': bg,
            'units': transUnits,
            'emergency': isCriticalGroup && (seconds % 6 == 0),
          });
        }
      }
    }

    final Map<String, dynamic> historicalData = {
      'donations': donations,
      'transfusions': transfusions,
    };

    try {
      final response = await http.post(
        registerUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _adminRegNameController.text,
          'phone': _adminRegPhoneController.text,
          'password': _adminRegPasswordController.text,
          'address': _adminRegAddressController.text,
          'establishment_date': _adminRegSelectedEstDate.toIso8601String().split('T')[0],
          'website_link': _adminRegWebsiteController.text,
          'approval_document_base64': _adminRegSelectedDoc?.base64Content,
          'approval_document_name': _adminRegSelectedDoc?.name,
          'location_lat': lat,
          'location_lng': lng,
          'region_name': _adminRegSelectedRegion,
          'inventory_data': inventoryData,
          'historical_data': historicalData,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final uid = data['profile']['firebase_uid'];
        final role = data['role'] ?? 'bank_admin';
        final profile = data['profile'];
        final token = data['token'] ?? '';
        
        await state.login(role, uid, profile, token: token);
      } else {
        final errorData = jsonDecode(response.body);
        setState(() {
          _errorMessage = _parseErrorDetail(errorData['detail'], fallback: 'Registration failed.');
          _isVerifying = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error establishing connection: $e';
        _isVerifying = false;
      });
    }
  }

  double _randomJitter(double maxVal) {
    return (DateTime.now().millisecond % 100) / 100.0 * maxVal;
  }
}

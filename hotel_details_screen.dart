import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:math';

import '../translations.dart';

class HotelDetailsScreen extends StatefulWidget {
  final String hotelKey;
  final String hotelRawName;
  final String currentLang;
  final Map<String, dynamic>? currentUser;

  const HotelDetailsScreen({
    Key? key,
    required this.hotelKey,
    required this.hotelRawName,
    required this.currentLang,
    required this.currentUser,
  }) : super(key: key);

  @override
  State<HotelDetailsScreen> createState() => _HotelDetailsScreenState();
}

class _HotelDetailsScreenState extends State<HotelDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  Map<String, List<Map<String, dynamic>>> _services = {
    'rooms': [],
    'restaurant': [],
    'pool': [],
    'spa': [],
    'club': [],
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadHotelServices();
  }

  void _loadHotelServices() {
    _dbRef
        .child('hotels/${widget.hotelKey}/services')
        .onValue
        .listen((event) {
      if (event.snapshot.value != null) {
        Map data = event.snapshot.value as Map;
        Map<String, List<Map<String, dynamic>>> temp = {
          'rooms': [],
          'restaurant': [],
          'pool': [],
          'spa': [],
          'club': [],
        };

        data.forEach((k, v) {
          Map<String, dynamic> item = Map<String, dynamic>.from(v);
          String cat = item['category'] ?? 'rooms';
          if (temp.containsKey(cat)) {
            temp[cat]!.add(item);
          }
        });

        setState(() {
          _services = temp;
        });
      }
    });
  }

  void _initiateBooking(Map<String, dynamic> item) {
    if (widget.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Please sign in first!")),
      );
      return;
    }
    _showPaymentModal(item);
  }

  void _showPaymentModal(Map<String, dynamic> item) {
    String t(String key) =>
        AppTranslations.getText(key, widget.currentLang);

    TextEditingController nameCtrl = TextEditingController(
        text: widget.currentUser?['name'] ?? '');
    TextEditingController phoneCtrl = TextEditingController(
        text: widget.currentUser?['phone'] ?? '');
    TextEditingController txCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            t('payModalTitle'),
            style: const TextStyle(color: Color(0xFFDFB15B)),
            textAlign: TextAlign.center,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Price: ${item['price']} ETB",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.amber.withOpacity(0.1),
                  child: Text(t('paymentOptions')),
                ),
                TextField(
                    controller: nameCtrl,
                    decoration:
                        InputDecoration(labelText: t('payLblName'))),
                TextField(
                    controller: phoneCtrl,
                    decoration:
                        InputDecoration(labelText: t('payLblPhone'))),
                TextField(
                    controller: txCtrl,
                    decoration: InputDecoration(labelText: t('payLblTx'))),
                const SizedBox(height: 15),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDFB15B),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    if (txCtrl.text.isEmpty) return;
                    Navigator.pop(context);
                    _submitBooking(
                        item, nameCtrl.text, phoneCtrl.text, txCtrl.text);
                  },
                  child: Text(t('btnPaySubmit')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _submitBooking(
      Map<String, dynamic> item, String name, String phone, String txRef) {
    String orderId = 'ORD-${100000 + Random().nextInt(900000)}';
    String qrCodeToken =
        'QR-ONE-TIME-${Random().nextInt(1000000).toString().padLeft(8, '0')}';

    Map<String, dynamic> orderData = {
      'id': orderId,
      'qrCode': qrCodeToken,
      'hotelId': widget.hotelKey,
      'service': item['title'] ?? item['name'],
      'price': item['price'],
      'customer': "$name (Email: ${widget.currentUser?['email']}, Phone: $phone)",
      'customerName': name,
      'phone': phone,
      'email': widget.currentUser?['email'] ?? '',
      'txRef': txRef,
      'status': "pending",
      'used': false,
      'timestamp': DateTime.now().toString(),
      'createdAt': DateTime.now().millisecondsSinceEpoch
    };

    String newOrderKey = _dbRef.child('orders').push().key!;
    Map<String, dynamic> updates = {};
    updates['/orders/$newOrderKey'] = orderData;
    updates['/hotels/${widget.hotelKey}/orders/$newOrderKey'] = orderData;

    _dbRef.update(updates).then((_) {
      _showQrModal(qrCodeToken);
    });
  }

  void _showQrModal(String qrToken) {
    String t(String key) =>
        AppTranslations.getText(key, widget.currentLang);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t('qrModalTitle'),
              style: const TextStyle(color: Color(0xFFDFB15B)),
              textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('qrModalDesc'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 15),
              SizedBox(
                width: 180,
                height: 180,
                child: QrImageView(
                  data: qrToken,
                  version: QrVersions.auto,
                  size: 180.0,
                ),
              ),
              const SizedBox(height: 10),
              Text("Code: $qrToken",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFDFB15B))),
              const SizedBox(height: 15),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: Text(t('qrDoneBtn')),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryGrid(List<Map<String, dynamic>> items) {
    String t(String key) =>
        AppTranslations.getText(key, widget.currentLang);

    if (items.isEmpty) {
      return const Center(child: Text("No items available"));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 15),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 160,
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                  image: DecorationImage(
                    image: NetworkImage(item['img'] ??
                        'https://images.unsplash.com/photo-1540541338287-41700207dee6?q=80&w=400'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['title'] ?? item['name'] ?? '',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(item['desc'] ?? item['description'] ?? '',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text("${item['price']} ETB",
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFDFB15B))),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDFB15B),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () => _initiateBooking(item),
                        child: Text(t('bookBtn')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String displayHotelName = AppTranslations.getTranslatedHotelName(
        widget.hotelRawName, widget.currentLang);
    String t(String key) =>
        AppTranslations.getText(key, widget.currentLang);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(
          "${displayHotelName.toUpperCase()} - ${t('servicesTag')}",
          style: const TextStyle(color: Color(0xFFDFB15B), fontSize: 16),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: const Color(0xFFDFB15B),
          labelColor: const Color(0xFFDFB15B),
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(text: t('tabRooms')),
            Tab(text: t('tabRest')),
            Tab(text: t('tabPool')),
            Tab(text: t('tabSpa')),
            Tab(text: t('tabClub')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCategoryGrid(_services['rooms']!),
          _buildCategoryGrid(_services['restaurant']!),
          _buildCategoryGrid(_services['pool']!),
          _buildCategoryGrid(_services['spa']!),
          _buildCategoryGrid(_services['club']!),
        ],
      ),
    );
  }
}

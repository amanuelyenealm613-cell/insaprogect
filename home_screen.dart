import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:math';

import '../main.dart';
import '../translations.dart';
import 'hotel_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  String _currentLang = 'am';
  List<Map<String, dynamic>> _allHotelsData = [];
  List<Map<String, dynamic>> _filteredHotels = [];
  Map<String, dynamic>? _currentUser;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _custNameController = TextEditingController();
  final TextEditingController _custPhoneController = TextEditingController();
  final TextEditingController _custEmailController = TextEditingController();

  // AI Assistant Chat State
  final List<Map<String, String>> _aiMessages = [];
  final TextEditingController _aiInputController = TextEditingController();
  bool _isAiModalOpen = false;

  @override
  void initState() {
    super.initState();
    _loadSavedUserAndLang();
    _fetchHotels();
  }

  Future<void> _loadSavedUserAndLang() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentLang = prefs.getString('adane_lang') ?? 'am';
      String? userStr = prefs.getString('adane_customer');
      if (userStr != null) {
        _currentUser = jsonDecode(userStr);
        _custEmailController.text = _currentUser!['email'] ?? '';
        _custNameController.text = _currentUser!['name'] ?? '';
        _custPhoneController.text = _currentUser!['phone'] ?? '';
      }
    });
  }

  void _fetchHotels() {
    _dbRef.child('hotels').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        List<Map<String, dynamic>> loaded = [];
        data.forEach((key, value) {
          if (key != 'hotel_005' && key != 'htoel_005' && value != null) {
            Map<String, dynamic> hData = Map<String, dynamic>.from(value);
            if (hData.containsKey('info')) {
              hData = {...Map<String, dynamic>.from(hData['info']), ...hData};
            }
            loaded.add({'key': key, 'data': hData});
          }
        });
        setState(() {
          _allHotelsData = loaded;
          _filteredHotels = loaded;
        });
      }
    });
  }

  void _filterHotels(String query) {
    String q = query.toLowerCase().trim();
    setState(() {
      _filteredHotels = _allHotelsData.where((item) {
        String rawName = item['data']['name'] ?? '';
        String displayHotelName =
            AppTranslations.getTranslatedHotelName(rawName, _currentLang)
                .toLowerCase();
        String location = (item['data']['location'] ?? '').toLowerCase();
        return rawName.toLowerCase().contains(q) ||
            displayHotelName.contains(q) ||
            location.contains(q);
      }).toList();
    });
  }

  void _changeLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('adane_lang', lang);
    setState(() {
      _currentLang = lang;
    });
  }

  // GOOGLE LOGIN
  Future<void> _openGoogleLogin() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser != null) {
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        UserCredential userCred = await _auth.signInWithCredential(credential);
        User? profile = userCred.user;

        if (profile != null) {
          Map<String, dynamic> userData = {
            'email': profile.email ?? '',
            'name': profile.displayName ?? '',
            'phone': _currentUser?['phone'] ?? '',
            'profilePic': profile.photoURL ?? ''
          };

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('adane_customer', jsonEncode(userData));

          setState(() {
            _currentUser = userData;
            _custEmailController.text = userData['email'];
            _custNameController.text = userData['name'];
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("✅ Success: ${profile.displayName}")),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("⚠️ Error: ${e.toString()}")),
      );
    }
  }

  void _saveCustomerAccount() async {
    if (_custEmailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Please sign in with Google first!")),
      );
      return;
    }
    Map<String, dynamic> userData = {
      'email': _custEmailController.text,
      'name': _custNameController.text,
      'phone': _custPhoneController.text,
      'profilePic': _currentUser?['profilePic'] ?? ''
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('adane_customer', jsonEncode(userData));

    setState(() {
      _currentUser = userData;
    });

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ Profile saved successfully!")),
    );
  }

  void _logoutCustomer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('adane_customer');
    await _auth.signOut();
    await _googleSignIn.signOut();
    setState(() {
      _currentUser = null;
      _custEmailController.clear();
      _custNameController.clear();
      _custPhoneController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🚪 Logged out.")),
    );
  }

  // AI HEALTH ADVISOR LOGIC
  void _sendAiMessage() {
    String text = _aiInputController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _aiMessages.add({'role': 'user', 'text': text});
      _aiInputController.clear();
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      String reply = _generateSmartAiResponse(text);
      setState(() {
        _aiMessages.add({'role': 'bot', 'text': reply});
      });
    });
  }

  String _generateSmartAiResponse(String userQuery) {
    String q = userQuery.toLowerCase();
    String lang = _currentLang;

    if (q.contains('ስኳር') ||
        q.contains('ደም ግፊት') ||
        q.contains('diab') ||
        q.contains('sukkaara') ||
        q.contains('ጽግያት')) {
      if (lang == 'en')
        return "<b>For Diabetes & Blood Pressure:</b><br>• High fiber foods, zero sugar and low salt diets.<br>• Boiled chicken or fish.";
      if (lang == 'om')
        return "<b>Dhukkubsattoota Sukkaaraa & Dhiibbaa Dhiigaatiif:</b><br>• Nyaata faayibarii qaban, nyaata sukkaraafi soogidda hin qabne.<br>• Foon kukkullaa ykn qurxummii.";
      if (lang == 'ti')
        return "<b>ንሕማም ስኳርን ጸቕጢ ደምን፦</b><br>• ፋይበር ዘለዎም፣ ስኳርን ጨውን ዘይብሎም ምግቢ።<br>• እተፈልሐ ደርሆን ዓሳን።";
      return "<b>ለስኳር እና ደም ግፊት ታማሚዎች የሚመከሩ ምግቦች፦</b><br>• በፋይበር የበለፀጉ፣ ስኳር እና ጨው የሌላቸው ምግቦች<br>• የተቀቀለ ዶሮ ወይም አሳ።";
    }

    if (q.contains('ልብ') || q.contains('heart')) {
      if (lang == 'en')
        return "<b>For Heart Health:</b><br>• Fat-free foods like boiled vegetables, fish, and olive oil.<br>• Avoid fried and fatty foods.";
      return "<b>ለልብ ጤንነት የሚመከሩ፦</b><br>• ቅባት የሌላቸው እንደ የተቀቀለ አትክልት፣ አሳ እና የኦሊቭ ዘይት ያላቸው ምግቦች<br>• የተጠበሱ እና ቅባታማ ምግቦችን ማስወገድ።";
    }

    if (q.contains('ወባ') ||
        q.contains('በሽታ') ||
        q.contains('ህመም') ||
        q.contains('ትኩሳት') ||
        q.contains('malaria')) {
      if (lang == 'en')
        return "<b>For Malaria & Fever:</b><br>• Get plenty of fluids (water, fresh juice, chicken soup).<br>• Vitamin C rich fruits.";
      return "<b>ለወባ እና ትኩሳት ህመምተኞች የሚመከሩ፦</b><br>• ብዙ ፈሳሽ ማግኘት (ውሃ፣ አዲስ የተጨመቀ የፍራፍሬ ጁስ፣ የዶሮ ሾርባ)<br>• በቫይታሚን ሲ የበለፀጉ ፍራፍሬዎች።";
    }

    if (q.contains('ምርጥ') ||
        q.contains('ሆቴል') ||
        q.contains('hotel') ||
        q.contains('hoteela')) {
      if (_allHotelsData.isEmpty) return "No hotels found.";
      String hotelNames = _allHotelsData
          .map((h) =>
              "• " +
              AppTranslations.getTranslatedHotelName(
                  h['data']['name'] ?? h['key'], _currentLang))
          .join("<br>");
      return (lang == 'en' ? "<b>Best Hotels:</b><br>" : "<b>ምርጥ ሆቴሎች፦</b><br>") +
          hotelNames;
    }

    if (lang == 'en')
      return "I am your Hotel and Health AI Advisor! You can ask me anything about hotels, room prices, fitness, diet, diabetes, blood pressure, heart health, or malaria.";
    if (lang == 'om')
      return "Ani gorsaa AIiti. Waa'ee hoteelotaa, nyaataafi fayyaa gaafachuu dandeessu.";
    if (lang == 'ti')
      return "ኣነ ናይ ሆቴልን ጥዕናን AI አማካሪ እየ! ዝኾነ ሕቶ ክትሕቱ ትኽእሉ።";
    return "እኔ የሆቴል እና የጤና AI አማካሪዎ ነኝ! ማንኛውንም ጥያቄ መጠየቅ ይችላሉ።";
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppTranslations.getText(key, _currentLang);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF003580),
        title: SizedBox(
          height: 40,
          child: TextField(
            controller: _searchController,
            onChanged: _filterHotels,
            decoration: InputDecoration(
              hintText: t('searchPlaceholder'),
              hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
              fillColor: Colors.white,
              filled: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(color: Colors.black),
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () => _openAccountModal(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: CircleAvatar(
                backgroundColor: const Color(0xFF2563EB),
                backgroundImage: (_currentUser != null &&
                        _currentUser!['profilePic'].toString().isNotEmpty)
                    ? NetworkImage(_currentUser!['profilePic'])
                    : null,
                child: (_currentUser == null ||
                        _currentUser!['profilePic'].toString().isEmpty)
                    ? const Text('Ⓐ', style: TextStyle(color: Colors.white))
                    : null,
              ),
            ),
          )
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF003580)),
              child: Center(
                child: Text(
                  t('menuTitle'),
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
            ),
            ListTile(
              title: Text(t('langLabel')),
              trailing: DropdownButton<String>(
                value: _currentLang,
                items: const [
                  DropdownMenuItem(value: 'am', child: Text('አማርኛ')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'om', child: Text('Afaan Oromoo')),
                  DropdownMenuItem(value: 'ti', child: Text('ትግርኛ')),
                ],
                onChanged: (val) {
                  if (val != null) _changeLanguage(val);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(t('historyMenu')),
              onTap: () {
                Navigator.pop(context);
                _openHistoryModal(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text(t('profileMenu')),
              onTap: () {
                Navigator.pop(context);
                _openAccountModal(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.brightness_6),
              title: Text(t('darkMode')),
              onTap: () {
                MyApp.of(context).toggleTheme();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title:
                  Text(t('logoutMenu'), style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _logoutCustomer();
              },
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Hotels Grid List
          _filteredHotels.isEmpty
              ? Center(child: Text(t('noHotels')))
              : ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: _filteredHotels.length,
                  itemBuilder: (context, index) {
                    final item = _filteredHotels[index];
                    final h = item['data'];
                    String rawName = h['name'] ?? item['key'];
                    String displayHotelName =
                        AppTranslations.getTranslatedHotelName(
                            rawName, _currentLang);
                    String img = h['img'] ?? h['logo'] ?? '';
                    String location = h['location'] ?? h['phone'] ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(15.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 21,
                              backgroundColor: const Color(0xFF003580),
                              backgroundImage:
                                  img.isNotEmpty ? NetworkImage(img) : null,
                              child: img.isEmpty
                                  ? Text(
                                      displayHotelName.isNotEmpty
                                          ? displayHotelName[0]
                                          : '',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayHotelName,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    location,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0071C2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => HotelDetailsScreen(
                                      hotelKey: item['key'],
                                      hotelRawName: rawName,
                                      currentLang: _currentLang,
                                      currentUser: _currentUser,
                                    ),
                                  ),
                                );
                              },
                              child: Text(
                                t('openBtn'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

          // AI Floating Button
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              backgroundColor: const Color(0xFF2563EB),
              child: const Text('🤖', style: TextStyle(fontSize: 22)),
              onPressed: () {
                setState(() {
                  _isAiModalOpen = !_isAiModalOpen;
                });
              },
            ),
          ),

          // AI Chat Assistant Widget Modal
          if (_isAiModalOpen)
            Positioned(
              bottom: 85,
              right: 20,
              width: 320,
              height: 420,
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: const Color(0xFF003580),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            t('aiHeader'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _isAiModalOpen = false),
                            child: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(10),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade800,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              t('aiWelcome'),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                          ),
                          ..._aiMessages.map((msg) {
                            bool isUser = msg['role'] == 'user';
                            return Align(
                              alignment: isUser
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? const Color(0xFF2563EB)
                                      : Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  msg['text']!
                                      .replaceAll('<b>', '')
                                      .replaceAll('</b>', '')
                                      .replaceAll('<br>', '\n'),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                ),
                              ),
                            );
                          }).toList()
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.black,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _aiInputController,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: t('aiPlaceholder'),
                                hintStyle: const TextStyle(color: Colors.grey),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDFB15B),
                              foregroundColor: Colors.black,
                            ),
                            onPressed: _sendAiMessage,
                            child: Text(t('aiSend')),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Account Modal
  void _openAccountModal(BuildContext context) {
    String t(String key) => AppTranslations.getText(key, _currentLang);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            t('authTitle'),
            style: const TextStyle(color: Color(0xFFDFB15B)),
            textAlign: TextAlign.center,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_currentUser != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundImage:
                              _currentUser!['profilePic'].isNotEmpty
                                  ? NetworkImage(_currentUser!['profilePic'])
                                  : null,
                          child: _currentUser!['profilePic'].isEmpty
                              ? Text(_currentUser!['name'][0])
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_currentUser!['name'],
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text(_currentUser!['email'],
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.login, color: Colors.blue),
                  label: Text(t('googleBtn')),
                  onPressed: _openGoogleLogin,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _custEmailController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: t('lblEmail'),
                    hintText: t('phEmail'),
                  ),
                ),
                TextField(
                  controller: _custNameController,
                  decoration: InputDecoration(
                    labelText: t('lblName'),
                    hintText: t('phName'),
                  ),
                ),
                TextField(
                  controller: _custPhoneController,
                  decoration: InputDecoration(
                    labelText: t('lblPhone'),
                    hintText: t('phPhone'),
                  ),
                ),
                const SizedBox(height: 15),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDFB15B),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _saveCustomerAccount,
                  child: Text(t('btnSubmitAccount')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // History Modal
  void _openHistoryModal(BuildContext context) {
    String t(String key) => AppTranslations.getText(key, _currentLang);

    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in first!")),
      );
      _openAccountModal(context);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              Text(
                t('historyModalTitle'),
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFDFB15B)),
              ),
              const SizedBox(height: 15),
              Expanded(
                child: StreamBuilder(
                  stream: _dbRef.child('orders').onValue,
                  builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
                    if (!snapshot.hasData ||
                        snapshot.data?.snapshot.value == null) {
                      return const Center(child: Text("No Orders"));
                    }
                    Map data = snapshot.data!.snapshot.value as Map;
                    List orders = [];
                    data.forEach((k, v) {
                      if (v['email'] == _currentUser!['email'] ||
                          (v['customer'] != null &&
                              v['customer'].contains(_currentUser!['email']))) {
                        orders.add(v);
                      }
                    });

                    return ListView.builder(
                      itemCount: orders.length,
                      itemBuilder: (context, index) {
                        var o = orders[index];
                        return Card(
                          child: ListTile(
                            title: Text(o['service'] ?? '-'),
                            subtitle: Text("ID: ${o['id'] ?? '-'}"),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("${o['price'] ?? 0} ETB"),
                                Text(
                                  o['used'] == true
                                      ? t('doneStatus')
                                      : (o['status'] ?? 'pending'),
                                  style: TextStyle(
                                    color: o['used'] == true
                                        ? Colors.red
                                        : Colors.green,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

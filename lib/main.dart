import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_apple/geolocator_apple.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

void main() {
  runApp(const GeofenceAlarmApp());
}

class Station {
  final String name;
  final double lat;
  final double lng;
  const Station(this.name, this.lat, this.lng);
}

const List<Station> javaStations = [
  Station("Purwokerto", -7.4194, 109.2222),
  Station("Kroya", -7.6300, 109.2450),
  Station("Kebumen", -7.6657, 109.6622),
  Station("Kutoarjo", -7.7262, 109.9070),
  Station("Wates", -7.8638, 110.1578),
  Station("Tugu Yogyakarta", -7.7892, 110.3635),
  Station("Lempuyangan", -7.7900, 110.3756),
  Station("Solo Balapan", -7.5570, 110.8213),
  Station("Bumiayu", -7.2424, 109.0069),
  Station("Prupuk", -7.1182, 108.9880),
  Station("Slawi", -6.9859, 109.1360),
  Station("Tegal", -6.8673, 109.1402),
  Station("Pemalang", -6.8856, 109.3887),
  Station("Pekalongan", -6.8894, 109.6749),
  Station("Semarang Poncol", -6.9722, 110.4140),
  Station("Semarang Tawang", -6.9644, 110.4279),
  Station("Cepu", -7.1517, 111.5833),
  Station("Bojonegoro", -7.1568, 111.8841),
  Station("Cirebon", -6.7053, 108.5554),
  Station("Gambir (Jakarta)", -6.1766, 106.8306),
  Station("Bandung", -6.9128, 107.6023),
];

class GeofenceAlarmApp extends StatelessWidget {
  const GeofenceAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AlarmScreen(),
    );
  }
}

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  Station? tempSelectedStation;
  List<Station> selectedRoute = [];
  int currentTargetIndex = 0;

  double radiusKm = 2.0; 
  final TextEditingController _radiusController = TextEditingController(text: "2.0");
  final TextEditingController _searchController = TextEditingController();
  
  String statusMessage = "Silakan buat rute dan tekan Mulai Pantau";
  bool isTracking = false;
  bool isAlarmRinging = false;
  StreamSubscription<Position>? positionStream;

  @override
  void initState() {
    super.initState();
  }

  void _addStationToRoute() {
    if (tempSelectedStation != null) {
      setState(() {
        selectedRoute.add(tempSelectedStation!);
        tempSelectedStation = null;
        _searchController.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ketik dan pilih stasiun dari daftar!'))
      );
    }
  }

  void _removeStationFromRoute(int index) {
    if (isTracking) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hentikan pantauan dulu untuk mengubah rute.'))
      );
      return;
    }
    setState(() {
      selectedRoute.removeAt(index);
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (isTracking) return;
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final Station item = selectedRoute.removeAt(oldIndex);
      selectedRoute.insert(newIndex, item);
    });
  }

  void _startTracking() async {
    if (selectedRoute.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daftar rute masih kosong!'))
      );
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => statusMessage = "Mohon aktifkan GPS");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => statusMessage = "Akses lokasi ditolak");
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      setState(() => statusMessage = "Akses lokasi ditolak permanen");
      return;
    }

    setState(() {
      isTracking = true;
      currentTargetIndex = 0;
      statusMessage = "Mencari lokasi...";
    });

    LocationSettings locationSettings;
    
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 50,
        forceLocationManager: true,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Sedang memantau jadwal stasiun berurutan...",
          notificationTitle: "Alarm Kereta Aktif",
          enableWakeLock: true,
        ),
      );
    } else if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS)) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.best,
        activityType: ActivityType.fitness,
        distanceFilter: 50,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 50,
      );
    }

    positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      _calculateDistance(position);
    });
  }

  void _stopTracking() {
    positionStream?.cancel();
    if (isAlarmRinging) _stopAlarmRingingOnly();
    setState(() {
      isTracking = false;
      currentTargetIndex = 0;
      statusMessage = "Pemantauan dihentikan.";
    });
  }

  void _calculateDistance(Position currentPosition) {
    if (selectedRoute.isEmpty || currentTargetIndex >= selectedRoute.length) return;

    Station currentTarget = selectedRoute[currentTargetIndex];

    double distanceInMeters = Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      currentTarget.lat,
      currentTarget.lng,
    );

    double radiusMeter = radiusKm * 1000;

    setState(() {
      if (distanceInMeters <= radiusMeter) {
        statusMessage = "BANGUN! Sudah dekat dengan Stasiun ${currentTarget.name} (Jarak: ${distanceInMeters.toStringAsFixed(0)}m)";
        
        if (!isAlarmRinging) {
          isAlarmRinging = true;
          _triggerAlarm();
        }
      } else {
        statusMessage = "Menuju: ${currentTarget.name}\nJarak: ${(distanceInMeters / 1000).toStringAsFixed(2)} km";
      }
    });
  }

  void _triggerAlarm() {
    if (!kIsWeb) {
      FlutterRingtonePlayer.playAlarm(
        looping: true, 
        volume: 1.0, 
        asAlarm: true, 
      );
    }
  }

  void _stopAlarmRingingOnly() {
    isAlarmRinging = false;
    if (!kIsWeb) {
      FlutterRingtonePlayer.stop();
    }
  }

  void _nextStation() {
    _stopAlarmRingingOnly();
    
    setState(() {
      if (currentTargetIndex < selectedRoute.length - 1) {
        // Lanjut stasiun berikutnya
        currentTargetIndex++;
        statusMessage = "Mencari lokasi menuju stasiun berikutnya...";
      } else {
        // Rute Selesai
        _stopTracking();
        statusMessage = "Perjalanan Selesai! Selamat datang di stasiun akhir.";
      }
    });
  }

  @override
  void dispose() {
    positionStream?.cancel();
    if (!kIsWeb) {
      FlutterRingtonePlayer.stop();
    }
    _radiusController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alarm Rute Kereta')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Tambah Stasiun ke Rute:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Autocomplete<Station>(
                    displayStringForOption: (Station option) => option.name,
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return const Iterable<Station>.empty();
                      }
                      return javaStations.where((Station option) {
                        return option.name.toLowerCase().contains(textEditingValue.text.toLowerCase());
                      });
                    },
                    onSelected: (Station selection) {
                      setState(() {
                        tempSelectedStation = selection;
                      });
                    },
                    fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                      // Sinkronisasi controller agar bisa di-clear
                      controller.addListener(() {
                        if (controller.text != _searchController.text) {
                           _searchController.text = controller.text;
                        }
                      });
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onEditingComplete: onEditingComplete,
                        decoration: InputDecoration(
                          hintText: "Cari stasiun...",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addStationToRoute,
                  child: const Text("Tambah"),
                )
              ],
            ),
            const SizedBox(height: 15),

            // Daftar Rute Aktif
            const Text("Daftar Rute (Tahan & Geser untuk urutkan):", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: selectedRoute.isEmpty
                  ? const Center(child: Text("Belum ada stasiun di rute", style: TextStyle(color: Colors.grey)))
                  : ReorderableListView.builder(
                      itemCount: selectedRoute.length,
                      onReorder: _onReorder,
                      itemBuilder: (context, index) {
                        final station = selectedRoute[index];
                        final bool isCurrentTarget = isTracking && index == currentTargetIndex;
                        final bool isPassed = isTracking && index < currentTargetIndex;

                        return ListTile(
                          key: ValueKey("${station.name}_$index"),
                          leading: CircleAvatar(
                            backgroundColor: isPassed ? Colors.grey : (isCurrentTarget ? Colors.blue : Colors.green),
                            child: Icon(
                              isPassed ? Icons.check : Icons.train, 
                              color: Colors.white, 
                              size: 20
                            ),
                          ),
                          title: Text(
                            "${index + 1}. ${station.name}", 
                            style: TextStyle(
                              decoration: isPassed ? TextDecoration.lineThrough : null,
                              fontWeight: isCurrentTarget ? FontWeight.bold : FontWeight.normal,
                              color: isPassed ? Colors.grey : Colors.black
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _removeStationFromRoute(index),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 20),
            
            const Text("Atur Radius Alarm (Berlaku untuk semua stasiun):", style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: radiusKm,
                    min: 0.5,
                    max: 20.0,
                    divisions: 39,
                    label: "${radiusKm.toStringAsFixed(1)} km",
                    onChanged: (value) {
                      setState(() {
                        radiusKm = value;
                        _radiusController.text = value.toStringAsFixed(1);
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: _radiusController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    onChanged: (value) {
                      double? parsed = double.tryParse(value);
                      if (parsed != null && parsed >= 0.5 && parsed <= 50.0) {
                        setState(() {
                          radiusKm = parsed;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Text("km"),
              ],
            ),
            
            const SizedBox(height: 30),
            Center(
              child: Icon(
                Icons.directions_subway, 
                size: 80, 
                color: isAlarmRinging ? Colors.red : (isTracking ? Colors.green : Colors.grey)
              ),
            ),
            const SizedBox(height: 20),
            Text(
              statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20, 
                fontWeight: FontWeight.bold,
                color: isAlarmRinging ? Colors.red : Colors.black87
              ),
            ),
            const SizedBox(height: 30),
            
            if (isAlarmRinging)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 15)
                ),
                onPressed: _nextStation,
                child: const Text('MATIKAN & LANJUT STASIUN BERIKUTNYA', style: TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center,),
              )
            else if (isTracking)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 15)
                ),
                onPressed: _stopTracking,
                child: const Text('Hentikan Perjalanan', style: TextStyle(color: Colors.white, fontSize: 18)),
              )
            else
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 15)
                ),
                onPressed: _startTracking,
                child: const Text('Mulai Perjalanan', style: TextStyle(color: Colors.white, fontSize: 18)),
              ),
          ],
        ),
      ),
    );
  }
}

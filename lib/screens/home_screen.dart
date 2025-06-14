// import 'dart:nativewrappers/_internal/vm/lib/ffi_native_type_patch.dart';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../services/water_data_service.dart';
import 'adaptive_map.dart';
import '../widgets/menu_bar.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import '../widgets/contaminant_sparkline.dart';
import '../widgets/location_summary_card.dart';
import '../widgets/alert_badge.dart';
import '../widgets/contaminant_heatmap.dart';
import 'comparison_dashboard.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class WaterQualityHomePage extends StatefulWidget {
  const WaterQualityHomePage({super.key});
  @override
  WaterQualityHomePageState createState() => WaterQualityHomePageState();
}

class WaterQualityHomePageState extends State<WaterQualityHomePage> {
  final Map<String, String> parameterNames = {
    '52644': 'PFOS',
    '53590': 'PFOS',
    '54084': 'PFOS',
    // '54117': 'PFOS',

    // '54137': 'PFOS',
    // '54205': 'PFOS',
    // '54206': 'PFOS',
    // '54248': 'PFOS',
    // '54280': 'PFOS',
    // '54312': 'PFOS',
    // '54673': 'PFOS',
    // '54674': 'PFOS',
    // '54675': 'PFOS',
    // '54784': 'PFOS',
    // '57926': 'PFOS',
    // '58010': 'PFOS',
    '53581': 'PFOA ion',
    '54083': 'PFOA ion',
    '54116': 'PFOA ion',
    // '54136': 'PFOA ion',
    // '54255': 'PFOA ion',
    // '54287': 'PFOA ion',
    // '54319': 'PFOA ion',
    // '54651': 'PFOA ion',
    // '54652': 'PFOA ion',
    // '54669': 'PFOA ion',
    // '54670': 'PFOA ion',
    // '54671': 'PFOA ion',
    // '54773': 'PFOA ion',
    // '57915': 'PFOA ion',
    // '57982': 'PFOA ion',
    // '58009': 'PFOA ion',
    // '63651': 'PFOA ion',
    // '65227': 'PFOA ion',
  };
  bool loading = false;
  LatLng? _currentPosition;
  LatLng? _newPosition;

  List<double> contaminantLimits = <double>[
    10.0,
    10.0,
    10_000_000.0,
    100.0,
    5_000.0,
  ]; // ppt
  List<Marker> _markers = [];
  List<dynamic> results = [];
  Map<String, dynamic>? _selectedLocation;
  bool _showSidebar = false;
  bool _showHeatmap = false;

  // ignore: unused_field, prefer_final_fields
  String _searchQuery = '';

  // ignore: unused_field, prefer_final_fields
  List<String> _suggestions = [];
  final TextEditingController _searchController = TextEditingController();

  // ignore: unused_field, prefer_final_fields
  bool _searching = false;

  Timer? _debounce;
  String? _selectedContaminant;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // universal contamination index (uci)
  double getUCI(
    double pfoaIon,
    double PFOS,
    double nitrates,
    double phosphates,
    double lead,
  ) {
    // normalize all the values to a linear scale, between 0 and the limit for that contaminant
    double normalizedPFOA =
        (pfoaIon.clamp(0, 2 * contaminantLimits[0])) / 2 * contaminantLimits[0];
    double normalizedPFOS =
        (PFOS.clamp(0, 2 * contaminantLimits[1])) / 2 * contaminantLimits[1];
    double normalizedNitrates =
        (nitrates.clamp(0, 2 * contaminantLimits[2])) /
        2 *
        contaminantLimits[2];
    double normalizedPhosphates =
        (phosphates.clamp(0, 2 * contaminantLimits[3])) /
        2 *
        contaminantLimits[3];
    double normalizedLead =
        (lead.clamp(0, 2 * contaminantLimits[4])) / 2 * contaminantLimits[4];

    double UCI =
        (normalizedPFOA +
            normalizedPFOS +
            normalizedNitrates +
            normalizedPhosphates +
            normalizedLead) /
        5;
    return UCI;
  }

  Future<void> _getCurrentLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        // Handle the case when permission is not granted
        return;
      }
    }
    final LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
    );
    Position position = await Geolocator.getCurrentPosition(
      locationSettings: locationSettings,
    );
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });
    await fetchLocations();
  }

  Future<void> fetchLocations() async {
    final target = _newPosition ?? _currentPosition;
    if (target == null) return;
    setState(() => loading = true);

    // Fetch all contaminant types (update as needed)
    await WaterDataService.fetchAll(
      latitude: target.latitude,
      longitude: target.longitude,
      radiusMiles: 20,
      contaminants: [
        ContaminantType.PFOAion,
        ContaminantType.Lead,
        ContaminantType.Nitrate,
        ContaminantType.Arsenic,
      ],
    );

    // Get all contaminant data as a map
    final allData =
        WaterDataService.getContaminantData([
              ContaminantType.PFOAion,
              ContaminantType.Lead,
              ContaminantType.Nitrate,
              ContaminantType.Arsenic,
            ])
            as Map<ContaminantType, dynamic>;

    // Combine all locations from all contaminants, tagging each with its type
    List<dynamic> locations = [];
    allData.forEach((type, data) {
      if (data is List) {
        for (final item in data) {
          item['__contaminantType'] = type.toString().split('.').last;
          locations.add(item);
        }
      }
    });

    setState(() {
      results = locations;
      // Group all records by unique location identifier first
      final Map<String, List<dynamic>> byLocation = {};
      for (final item in locations) {
        final locId = item['Location_Identifier']?.toString();
        if (locId == null) continue;
        byLocation.putIfAbsent(locId, () => []).add(item);
      }
      // Now, for each location, pick a representative item for coordinates
      final List<dynamic> uniqueLocations = byLocation.entries.map((entry) {
        // Use the first item for coordinates
        return entry.value.first;
      }).toList();
      // Filter valid locations with coordinates
      final validLocations = uniqueLocations.where((item) {
        double? lat =
            _parseDouble(item['Location_LatitudeStandardized']) ??
            _parseDouble(item['Location_Latitude']);
        double? lng =
            _parseDouble(item['Location_LongitudeStandardized']) ??
            _parseDouble(item['Location_Longitude']);
        return lat != null && lng != null;
      }).toList();
      // Sort by great circle distance to current location
      final Distance distance = Distance();
      validLocations.sort((a, b) {
        double latA =
            _parseDouble(a['Location_LatitudeStandardized']) ??
            _parseDouble(a['Location_Latitude'])!;
        double lngA =
            _parseDouble(a['Location_LongitudeStandardized']) ??
            _parseDouble(a['Location_Longitude'])!;
        double latB =
            _parseDouble(b['Location_LatitudeStandardized']) ??
            _parseDouble(b['Location_Latitude'])!;
        double lngB =
            _parseDouble(b['Location_LongitudeStandardized']) ??
            _parseDouble(b['Location_Longitude'])!;
        final dA = distance.as(
          LengthUnit.Kilometer,
          _currentPosition!,
          LatLng(latA, lngA),
        );
        final dB = distance.as(
          LengthUnit.Kilometer,
          _currentPosition!,
          LatLng(latB, lngB),
        );
        return dA.compareTo(dB);
      });
      final closest = validLocations.take(50).toList();
      // Now, for each of the closest locations, aggregate all contaminant records
      final Map<String, List<dynamic>> closestByLocation = {};
      for (final item in closest) {
        final locId = item['Location_Identifier']?.toString();
        if (locId == null) continue;
        closestByLocation[locId] = byLocation[locId]!;
      }
      // Filter by selected contaminant if set
      final filteredByLocation =
          (_selectedContaminant == null ||
              _selectedContaminant == 'Every Contaminant')
          ? closestByLocation.entries
          : closestByLocation.entries.where((entry) {
              final items = entry.value;
              final contaminantTypes = items
                  .map((item) => item['__contaminantType']?.toString())
                  .toSet();
              return contaminantTypes.contains(_selectedContaminant);
            });
      _markers = [
        // Black pin for current location
        Marker(
          point: _currentPosition!,
          width: 40,
          height: 40,
          child: Icon(Icons.location_on, color: Colors.black, size: 36),
        ),
        ...filteredByLocation.map<Marker>((entry) {
          final items = entry.value;
          final first = items.first;
          double lat = _parseDouble(first['Location_Latitude'])!;
          double lng = _parseDouble(first['Location_Longitude'])!;
          // Aggregate all contaminants and all historical records for this location
          final Map<String, List<Map<String, dynamic>>> byContaminant = {};
          for (final item in items) {
            final code =
                item['Result_Characteristic']?.toString() ??
                item['__contaminantType']?.toString() ??
                'Unknown';
            byContaminant.putIfAbsent(code, () => []).add(item);
          }
          final List<String> contaminantBlurbs = [];
          byContaminant.forEach((contaminantType, group) {
            // Sort by date ascending
            group.sort((a, b) {
              final aDate =
                  DateTime.tryParse(a['Activity_StartDate'] ?? '') ??
                  DateTime(1970);
              final bDate =
                  DateTime.tryParse(b['Activity_StartDate'] ?? '') ??
                  DateTime(1970);
              return aDate.compareTo(bDate);
            });
            final List<String> records = group
                .where((item) {
                  final value = double.tryParse(
                    item['Result_Measure']?.toString() ?? '',
                  );
                  return value != null && value > 0;
                })
                .map((item) {
                  final date = item['Activity_StartDate'] ?? '';
                  final value = item['Result_Measure'] ?? '';
                  final unit = item['Result_MeasureUnit'] ?? '';
                  return '  - ${date != '' ? 'Date: $date, ' : ''}Amount: $value $unit';
                })
                .toList();
            contaminantBlurbs.add(
              'Contaminant: $contaminantType\n${records.join('\n')}',
            );
          });
          final locationName = first['Location_Name']?.toString() ?? '';
          final info = [
            if (locationName.isNotEmpty) '[BOLD]Location: $locationName[/BOLD]',
            ...contaminantBlurbs,
          ].join('\n\n');
          // Find the contaminant with the highest latest value
          String? maxContaminant;
          double maxValue = double.negativeInfinity;
          byContaminant.forEach((contaminantType, group) {
            // Only consider records with a valid, nonzero value
            final validRecords = group.where((item) {
              final value = double.tryParse(
                item['Result_Measure']?.toString() ?? '',
              );
              return value != null && value > 0;
            }).toList();
            if (validRecords.isEmpty) return;
            // Find the latest record by date
            validRecords.sort((a, b) {
              final aDate =
                  DateTime.tryParse(a['Activity_StartDate'] ?? '') ??
                  DateTime(1970);
              final bDate =
                  DateTime.tryParse(b['Activity_StartDate'] ?? '') ??
                  DateTime(1970);
              return bDate.compareTo(aDate); // descending
            });
            final latest = validRecords.first;
            final latestValue =
                double.tryParse(latest['Result_Measure']?.toString() ?? '') ??
                0.0;
            if (latestValue > maxValue) {
              maxValue = latestValue;
              maxContaminant = contaminantType;
            }
          });
          Color getMarkerColor(String? type) {
            final colors = _contaminantColors();
            if (type != null && colors.containsKey(type)) {
              return colors[type]!;
            }
            return Colors.blue;
          }

          return Marker(
            point: LatLng(lat, lng),
            width: 40,
            height: 40,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                child: _CustomTooltip(
                  info: info,
                  onTap: () {
                    setState(() {
                      _selectedLocation = first;
                      _showSidebar = true;
                    });
                  },
                  child: Icon(
                    Icons.location_on,
                    color: getMarkerColor(maxContaminant),
                    size: 36,
                  ),
                ),
              ),
            ),
          );
        }),
      ];
      loading = false;
    });
  }

  void _updateMapCenter(LatLng center) {
    // Only update _newPosition if the user is not in the middle of a programmatic recenter
    // Remove the setState that updates _newPosition on every drag, so the map doesn't keep resetting its key
    // Instead, only update _newPosition when the user selects a new location or uses the search/my location button
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value);
    }
    return null;
  }

  Widget buildMap() {
    if (_currentPosition == null) {
      return Center(child: CircularProgressIndicator());
    }
    // Use kIsWeb to avoid Platform on web
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    final heatmapPoints = _buildHeatmapPoints();
    final heatmapValues = _buildHeatmapValues(heatmapPoints);
    final List<Widget> heatmapLayer = _showHeatmap
        ? [
            ContaminantHeatmap(
              points: heatmapPoints,
              values: heatmapValues,
              color: Colors.deepOrange,
              maxRadius: 100,
            ),
          ]
        : [];
    if (isDesktop) {
      return Row(
        children: [
          Expanded(
            flex: _showSidebar && _selectedLocation != null ? 3 : 2,
            child: Stack(
              children: [
                AdaptiveMap(
                  key: ValueKey(
                    _newPosition ?? _currentPosition,
                  ), // Use _newPosition for key
                  currentPosition: _newPosition ?? _currentPosition!,
                  markers: _markers,
                  onMapMoved: _updateMapCenter,
                  extraLayers: heatmapLayer,
                ),
                // Floating action button for dashboard
                Positioned(
                  top: 80,
                  right: 16,
                  child: FloatingActionButton.extended(
                    heroTag: 'dashboard',
                    backgroundColor: Colors.teal,
                    icon: Icon(Icons.dashboard),
                    label: Text('Compare'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ComparisonDashboard(
                            contaminantTrends: _buildTrends(),
                            dates: _buildDates(),
                            colors: [
                              Colors.teal,
                              Colors.orange,
                              Colors.red,
                              Colors.blue,
                            ],
                            contaminants: parameterNames.values
                                .toSet()
                                .toList(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  top: 80,
                  right: 16,
                  child: FloatingActionButton.extended(
                    heroTag: 'heatmap',
                    backgroundColor: Colors.deepOrange,
                    icon: Icon(Icons.thermostat),
                    label: Text('Heatmap'),
                    onPressed: () {
                      setState(() {
                        _showSidebar = false;
                        _selectedLocation = null;
                        _showHeatmap = !_showHeatmap;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_showSidebar && _selectedLocation != null)
            Container(
              width: 480, // wider sidebar
              color: Colors.white,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _showSidebar = false;
                        });
                      },
                    ),
                    LocationSummaryCard(
                      locationName: _selectedLocation?['Location_Name'] ?? '',
                      locationType:
                          _selectedLocation?['MonitoringLocationTypeName'] ??
                          '',
                      state: _selectedLocation?['StateCode'] ?? '',
                      contaminantValues: _buildContaminantValues(
                        _selectedLocation,
                      ),
                      contaminantColors: _contaminantColors(),
                    ),
                    if (_buildSparklines(_selectedLocation).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: Column(
                            children: _buildSparklines(_selectedLocation)
                                .map(
                                  (w) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4.0,
                                    ),
                                    child: w,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    if (_hasAlert(_selectedLocation))
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: AlertBadge(
                          show: true,
                          label: 'High Contaminant!',
                          color: Colors.red,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    // Mobile/web: overlay sidebar
    return Stack(
      children: [
        AdaptiveMap(
          key: ValueKey(
            _newPosition ?? _currentPosition,
          ), // Use _newPosition for key
          currentPosition: _newPosition ?? _currentPosition!,
          markers: _markers,
          onMapMoved: _updateMapCenter,
          extraLayers: heatmapLayer,
        ),
        Positioned(
          top: 80,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'dashboard',
            backgroundColor: Colors.teal,
            icon: Icon(Icons.dashboard),
            label: Text('Compare'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ComparisonDashboard(
                    contaminantTrends: _buildTrends(),
                    dates: _buildDates(),
                    colors: [
                      Colors.teal,
                      Colors.orange,
                      Colors.red,
                      Colors.blue,
                    ],
                    contaminants: parameterNames.values.toSet().toList(),
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          top: 80,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'heatmap',
            backgroundColor: Colors.deepOrange,
            icon: Icon(Icons.thermostat),
            label: Text('Heatmap'),
            onPressed: () {
              setState(() {
                _showSidebar = false;
                _selectedLocation = null;
                _showHeatmap = !_showHeatmap;
              });
            },
          ),
        ),
        if (_showSidebar && _selectedLocation != null)
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 300),
              width: 350,
              color: Colors.white,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _showSidebar = false;
                        });
                      },
                    ),
                    LocationSummaryCard(
                      locationName: _selectedLocation?['Location_Name'] ?? '',
                      locationType:
                          _selectedLocation?['MonitoringLocationTypeName'] ??
                          '',
                      state: _selectedLocation?['StateCode'] ?? '',
                      contaminantValues: _buildContaminantValues(
                        _selectedLocation,
                      ),
                      contaminantColors: _contaminantColors(),
                    ),
                    if (_buildSparklines(_selectedLocation).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: Column(
                            children: _buildSparklines(_selectedLocation)
                                .map(
                                  (w) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4.0,
                                    ),
                                    child: w,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    if (_hasAlert(_selectedLocation))
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: AlertBadge(
                          show: true,
                          label: 'High Contaminant!',
                          color: Colors.red,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // TODO: Kunj's manu bar
  Widget buildMenuBar() {
    return DropDown(
      value: _selectedContaminant,
      onChanged: (String? value) {
        setState(() {
          _selectedContaminant = value;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    return Scaffold(
      appBar: isDesktop
          ? AppBar(
              backgroundColor: Colors.white,
              title: Padding(
                padding: EdgeInsets.symmetric(horizontal: 80),
                child: Row(
                  children: [
                    Icon(Icons.water_drop_sharp, color: Colors.blue, size: 28),
                    SizedBox(width: 4),
                    Text(
                      'WaterWise',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
            )
          : AppBar(title: Text('WaterWise')),
      body: isDesktop
          ? Stack(
              children: [
                Positioned.fill(child: buildMap()),
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: _showSidebar ? 2 : 3,
                            child: TypeAheadField<Map<String, dynamic>>(
                              builder: (context, controller, focusNode) {
                                return Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 32,
                                    vertical: 12,
                                  ),
                                  child: TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    decoration: InputDecoration(
                                      hintText:
                                          'Search city, state, country, ZIP, etc.',
                                      prefixIcon: Icon(Icons.search),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                  ),
                                );
                              },
                              // callback every time user types
                              suggestionsCallback: (pattern) async {
                                if (_debounce?.isActive ?? false)
                                  _debounce!.cancel();
                                final completer =
                                    Completer<List<Map<String, dynamic>>>();
                                _debounce = Timer(
                                  const Duration(milliseconds: 500),
                                  () async {
                                    if (pattern.trim().isEmpty) {
                                      completer.complete([]);
                                      return;
                                    }
                                    final url = Uri.parse(
                                      'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(pattern)}&countrycodes=us&limit=10',
                                    );
                                    final response = await http.get(url);
                                    if (response.statusCode == 200) {
                                      final List data = jsonDecode(
                                        response.body,
                                      );
                                      completer.complete(
                                        data.cast<Map<String, dynamic>>(),
                                      );
                                      return;
                                    }
                                    completer.complete([]);
                                  },
                                );
                                return completer.future;
                              },
                              itemBuilder: (context, suggestion) {
                                final display =
                                    suggestion['display_name'] ?? '';
                                return ListTile(title: Text(display));
                              },
                              onSelected: (suggestion) {
                                _searchController.text =
                                    suggestion['display_name'] ?? '';
                                final lat = double.tryParse(
                                  suggestion['lat'] ?? '',
                                );
                                final lon = double.tryParse(
                                  suggestion['lon'] ?? '',
                                );
                                if (lat != null && lon != null) {
                                  setState(() {
                                    _currentPosition = LatLng(lat, lon);
                                    _newPosition = LatLng(lat, lon);
                                  });
                                  fetchLocations();
                                }
                              },
                              emptyBuilder: (context) {
                                if (_searchController.text.trim().isEmpty) {
                                  return SizedBox.shrink();
                                }
                                return const ListTile(
                                  title: Text('No items found!'),
                                );
                              },
                            ),
                          ),
                          SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              LocationPermission permission =
                                  await Geolocator.checkPermission();
                              if (permission == LocationPermission.denied ||
                                  permission ==
                                      LocationPermission.deniedForever) {
                                permission =
                                    await Geolocator.requestPermission();
                                if (permission == LocationPermission.denied ||
                                    permission ==
                                        LocationPermission.deniedForever) {
                                  return;
                                }
                              }
                              final LocationSettings locationSettings =
                                  LocationSettings(
                                    accuracy: LocationAccuracy.high,
                                  );
                              Position position =
                                  await Geolocator.getCurrentPosition(
                                    locationSettings: locationSettings,
                                  );
                              final userLatLng = LatLng(
                                position.latitude,
                                position.longitude,
                              );
                              setState(() {
                                _currentPosition = userLatLng;
                                _newPosition = userLatLng;
                              });
                              await fetchLocations();
                              setState(() {});
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              minimumSize: Size(0, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.my_location, color: Colors.red),
                                SizedBox(width: 4),
                                Text('My Location'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 0),
                              ),
                            ],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SizedBox(
                            height: 36,
                            child: ElevatedButton(
                              onPressed: fetchLocations,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                              child: Text('Refresh Water Data Nearby'),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32),
                        child: Container(
                          height: 36,
                          width: 400,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 0),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 0,
                            ),
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Choose contaminant:',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(child: buildMenuBar()),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (loading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black45,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            )
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TypeAheadField<Map<String, dynamic>>(
                                builder: (context, controller, focusNode) =>
                                    TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      decoration: InputDecoration(
                                        hintText:
                                            'Search city, state, country, zip, etc.',
                                        prefixIcon: Icon(Icons.search),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                suggestionsCallback: (pattern) async {
                                  if (_debounce?.isActive ?? false)
                                    _debounce!.cancel();
                                  final completer =
                                      Completer<List<Map<String, dynamic>>>();
                                  _debounce = Timer(
                                    const Duration(milliseconds: 500),
                                    () async {
                                      if (pattern.trim().isEmpty) {
                                        completer.complete([]);
                                        return;
                                      }
                                      final url = Uri.parse(
                                        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(pattern)}&countrycodes=us&limit=10',
                                      );
                                      final response = await http.get(url);
                                      if (response.statusCode == 200) {
                                        final List data = jsonDecode(
                                          response.body,
                                        );
                                        completer.complete(
                                          data.cast<Map<String, dynamic>>(),
                                        );
                                        return;
                                      }
                                      completer.complete([]);
                                    },
                                  );
                                  return completer.future;
                                },
                                itemBuilder: (context, suggestion) {
                                  final display =
                                      suggestion['display_name'] ?? '';
                                  return ListTile(title: Text(display));
                                },
                                onSelected: (suggestion) {
                                  _searchController.text =
                                      suggestion['display_name'] ?? '';
                                  final lat = double.tryParse(
                                    suggestion['lat'] ?? '',
                                  );
                                  final lon = double.tryParse(
                                    suggestion['lon'] ?? '',
                                  );
                                  if (lat != null && lon != null) {
                                    setState(() {
                                      _currentPosition = LatLng(lat, lon);
                                      _newPosition = LatLng(lat, lon);
                                    });
                                    fetchLocations();
                                  }
                                },
                                emptyBuilder: (context) {
                                  if (_searchController.text.trim().isEmpty) {
                                    return SizedBox.shrink();
                                  }
                                  return const ListTile(
                                    title: Text('No items found!'),
                                  );
                                },
                              ),
                            ),
                            SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () async {
                                LocationPermission permission =
                                    await Geolocator.checkPermission();
                                if (permission == LocationPermission.denied ||
                                    permission ==
                                        LocationPermission.deniedForever) {
                                  permission =
                                      await Geolocator.requestPermission();
                                  if (permission == LocationPermission.denied ||
                                      permission ==
                                          LocationPermission.deniedForever) {
                                    return;
                                  }
                                }
                                final LocationSettings locationSettings =
                                    LocationSettings(
                                      accuracy: LocationAccuracy.high,
                                    );
                                Position position =
                                    await Geolocator.getCurrentPosition(
                                      locationSettings: locationSettings,
                                    );
                                final userLatLng = LatLng(
                                  position.latitude,
                                  position.longitude,
                                );
                                setState(() {
                                  _currentPosition = userLatLng;
                                  _newPosition = userLatLng;
                                });
                                await fetchLocations();
                                setState(() {});
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.my_location),
                                  SizedBox(width: 4),
                                  Text('My Location'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: fetchLocations,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                          child: Text('Refresh Water Data Nearby'),
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Choose contaminant:',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(child: buildMenuBar()),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (loading)
                    Expanded(child: Center(child: CircularProgressIndicator()))
                  else
                    Expanded(child: Stack(children: [buildMap()])),
                ],
              ),
            ),
    );
  }

  Map<String, List<double>> _buildTrends() {
    // Example: build time series for each contaminant (mocked for now)
    final Map<String, List<double>> trends = {};
    for (var code in parameterNames.keys) {
      trends[parameterNames[code] ?? code] = List.generate(
        10,
        (i) => (i + 1) * 2.0,
      );
    }
    return trends;
  }

  List<DateTime> _buildDates() {
    // Example: 10 days
    return List.generate(
      10,
      (i) => DateTime.now().subtract(Duration(days: 10 - i)),
    );
  }

  Map<String, double> _buildContaminantValues(Map<String, dynamic>? location) {
    // Use the new shared function for consistency
    final series = buildContaminantSeries(location);
    final Map<String, double> values = {};
    for (final entry in series.entries) {
      values[entry.key] = entry.value['latest'] ?? 0.0;
    }
    return values;
  }

  /// Returns a map of contaminant name -> (latest value, full time series, full date series)
  Map<String, Map<String, dynamic>> buildContaminantSeries(
    Map<String, dynamic>? location,
  ) {
    if (location == null) return {};
    final locationId = location['Location_Identifier']?.toString();
    final allResults = results
        .where(
          (item) =>
              item['Location_Identifier']?.toString() == locationId &&
              item['Result_Measure'] != null &&
              item['Result_Characteristic'] != null,
        )
        .toList();
    final Map<String, List<Map<String, dynamic>>> byContaminant = {};
    for (final item in allResults) {
      final code = item['Result_Characteristic']?.toString();
      if (code == null) continue;
      byContaminant.putIfAbsent(code, () => []).add(item);
    }
    final Map<String, Map<String, dynamic>> result = {};
    for (final code in byContaminant.keys) {
      final group = byContaminant[code]!;
      // Sort by date ascending
      group.sort((a, b) {
        final aDate =
            DateTime.tryParse(a['Activity_StartDate'] ?? '') ?? DateTime(1970);
        final bDate =
            DateTime.tryParse(b['Activity_StartDate'] ?? '') ?? DateTime(1970);
        return aDate.compareTo(bDate);
      });
      final values = group
          .map(
            (e) =>
                double.tryParse(e['Result_Measure']?.toString() ?? '') ?? 0.0,
          )
          .toList();
      final dates = group
          .map(
            (e) =>
                DateTime.tryParse(e['Activity_StartDate'] ?? '') ??
                DateTime(1970),
          )
          .toList();
      if (values.isEmpty) continue;
      final name =
          (group.first['Result_Characteristic'] != null &&
              group.first['Result_Characteristic'].toString().trim().isNotEmpty)
          ? group.first['Result_Characteristic'].toString().trim()
          : (parameterNames[code] ?? code);
      result[name] = {'latest': values.last, 'series': values, 'dates': dates};
    }
    return result;
  }

  Map<String, Color> _contaminantColors() {
    return {
      'PFOA ion': Colors.blue,
      'Lead': Colors.red,
      'Nitrate': Colors.orange,
      'Arsenic': Colors.green,
    };
  }

  List<Widget> _buildSparklines(Map<String, dynamic>? location) {
    final series = buildContaminantSeries(location);
    final List<Widget> sparklines = [];
    series.forEach((name, data) {
      final values = (data['series'] as List<double>);
      final dates = (data['dates'] as List<DateTime>);
      if (values.isEmpty) return;
      sparklines.add(
        ContaminantSparkline(
          values: values,
          dates: dates,
          color: _contaminantColors()[name] ?? Colors.teal,
          label: name,
          latestValue: values.last,
        ),
      );
    });
    if (sparklines.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('No contaminant data available for this location.'),
        ),
      ];
    }
    return sparklines;
  }

  bool _hasAlert(Map<String, dynamic>? location) {
    if (location == null) return false;
    // Example: alert if any value > 10
    for (var code in parameterNames.keys) {
      final val = double.tryParse(location[code]?.toString() ?? '');
      if (val != null && val > 10) return true;
    }
    return false;
  }

  // Returns a tuple of (points, values) where each point always has a value (0 if missing)
  List<LatLng> _buildHeatmapPoints() {
    // Use all unique locations with valid coordinates
    final Set<String> seen = {};
    final List<LatLng> uniquePoints = [];
    for (final item in results) {
      final lat = _parseDouble(item['Location_Latitude']);
      final lng = _parseDouble(item['Location_Longitude']);
      if (lat != null && lng != null) {
        final key = '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
        if (!seen.contains(key)) {
          seen.add(key);
          uniquePoints.add(LatLng(lat, lng));
        }
      }
    }
    return uniquePoints;
  }

  List<double> _buildHeatmapValues(List<LatLng> points) {
    // For each point, find the max value at that location, or 0 if none
    final Map<String, List<double>> valuesByLocation = {};
    for (final item in results) {
      final lat = _parseDouble(item['Location_Latitude']);
      final lng = _parseDouble(item['Location_Longitude']);
      final valRaw = item['Result_Measure'];
      final val = (valRaw == null || valRaw.toString().trim().isEmpty)
          ? null
          : double.tryParse(valRaw.toString());
      if (lat != null && lng != null && val != null && val > 0) {
        final key = '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
        valuesByLocation.putIfAbsent(key, () => []).add(val);
      }
    }
    return points.map((pt) {
      final key =
          '${pt.latitude.toStringAsFixed(5)},${pt.longitude.toStringAsFixed(5)}';
      final vals = valuesByLocation[key];
      if (vals == null || vals.isEmpty) return 0.0;
      return vals.reduce((a, b) => a > b ? a : b);
    }).toList();
  }
}

class _CustomTooltip extends StatefulWidget {
  final String info;
  final Widget child;
  final VoidCallback? onTap;
  const _CustomTooltip({required this.info, required this.child, this.onTap});

  @override
  State<_CustomTooltip> createState() => _CustomTooltipState();
}

class _CustomTooltipState extends State<_CustomTooltip> {
  OverlayEntry? _overlayEntry;
  bool _isHovering = false;
  bool _overlayVisible = false;

  void _showOverlay(BuildContext context, Offset position) {
    if (_overlayVisible) return;
    _overlayVisible = true;
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: position.dx + 50,
        top: position.dy - 12,
        child: MouseRegion(
          onEnter: (_) {
            _isHovering = true;
          },
          onExit: (_) {
            _isHovering = false;
            _removeOverlay();
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(2, 2),
                  ),
                ],
              ),
              child: _buildRichContent(),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    if (!_overlayVisible) return;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _overlayVisible = false;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (event) {
        _isHovering = true;
        final renderBox = context.findRenderObject() as RenderBox;
        final offset = renderBox.localToGlobal(Offset.zero);
        _showOverlay(context, offset);
      },
      onExit: (event) {
        _isHovering = false;
        // Delay removal to allow entering overlay
        Future.delayed(Duration(milliseconds: 100), () {
          if (!_isHovering) _removeOverlay();
        });
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          if (widget.onTap != null) {
            widget.onTap!();
          } else {
            showDialog(
              context: context,
              builder: (ctx) {
                return AlertDialog(
                  content: _buildRichContent(),
                  contentPadding: EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              },
            );
          }
        },
        child: widget.child,
      ),
    );
  }

  Widget _buildRichContent() {
    final lines = widget.info.split('\n\n');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        if (line.startsWith('[BOLD]') && line.endsWith('[/BOLD]')) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              line.replaceAll('[BOLD]', '').replaceAll('[/BOLD]', ''),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(line, style: TextStyle(fontSize: 13)),
        );
      }).toList(),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }
}

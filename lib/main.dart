import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:liskfitai/fitcoin_service.dart';

void main() => runApp(HealthApp());

class HealthApp extends StatefulWidget {
  @override
  _HealthAppState createState() => _HealthAppState();
}

enum AppState {
  DATA_NOT_FETCHED,
  FETCHING_DATA,
  DATA_READY,
  NO_DATA,
  AUTHORIZED,
  AUTH_NOT_GRANTED,
  STEPS_READY,
}

class _HealthAppState extends State<HealthApp> {
  List<HealthDataPoint> _healthDataList = [];
  AppState _state = AppState.DATA_NOT_FETCHED;
  late FitCoinService newFitCoinService;
  double _balanceFitCoin = 0.0;
  int? _loadingIndex;
  List<int> _claimedRewards = [];
  // loading claimn
  bool _loading = false;
  List<HealthDataType> get types => [
        HealthDataType.STEPS,
        HealthDataType.WEIGHT,
        //HealthDataType.ACTIVE_ENERGY_BURNED,
        // HealthDataType.HEART_RATE,
        // HealthDataType.BLOOD_GLUCOSE
      ];

  List<HealthDataAccess> get permissions =>
      types.map((e) => HealthDataAccess.READ).toList();

  @override
  void initState() {
    super.initState();
    _initializeAsyncDependencies();
  }

  Future<void> _initializeAsyncDependencies() async {
    try {
      await dotenv.load();
    } catch (e) {
      print("Error al cargar .env: $e");
    }
    Health().configure(useHealthConnectIfAvailable: true);
    newFitCoinService = FitCoinService();
    double balance = await newFitCoinService
        .getBalance("0xA412741a7f39E45E0baAAB9B7C8eEc6D700e2c2c");
    setState(() {
      _balanceFitCoin = balance;
    });
  }

  Future<void> authorize() async {
    await Permission.activityRecognition.request();
    await Permission.location.request();
    bool authorized = await Health().requestAuthorization(types);
    setState(() {
      _state = authorized ? AppState.AUTHORIZED : AppState.AUTH_NOT_GRANTED;
    });
  }

  Future<void> fetchData() async {
    setState(() => _state = AppState.FETCHING_DATA);

    final now = DateTime.now();
    final yesterday = now.subtract(Duration(hours: 24));
    _healthDataList.clear();

    try {
      List<HealthDataPoint> healthData = await Health().getHealthDataFromTypes(
        types: types,
        startTime: yesterday,
        endTime: now,
      );
      _healthDataList = Health().removeDuplicates(healthData);
      print(_healthDataList.toString());
      setState(() {
        _state =
            _healthDataList.isEmpty ? AppState.NO_DATA : AppState.DATA_READY;
      });
    } catch (e) {
      debugPrint("Error fetching health data: $e");
      setState(() => _state = AppState.NO_DATA);
    }
  }

  int calculateTotalSteps(List<HealthDataPoint> healthDataPoints) {
    int totalSteps = 0;
    for (var point in healthDataPoints) {
      if (point.type == HealthDataType.STEPS) {
        totalSteps +=
            (point.value as NumericHealthValue).numericValue?.toInt() ?? 0;
      }
    }
    return totalSteps;
  }

  @override
  Widget build(BuildContext context) {
    int totalSteps = calculateTotalSteps(_healthDataList);

    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.only(
                left: 21.0, right: 21.0, top: 25.0, bottom: 10.0),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      // Fancy title: LiskFit AI Rewards
                      Text(
                        'LiskFit AI Rewards',
                        style: TextStyle(
                          color: Colors.deepPurpleAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      /// display wallet 0xA412741a7f39E45E0baAAB9B7C8eEc6D700e2c2c with overflow ellipsis
                      Text(
                        '0xA412741a7f39E45E0baAAB9B7C8eEc6D700e2c2c',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      /// display balance of FitCoin
                      Text(
                        'Balance: $_balanceFitCoin',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Divider(color: Colors.deepPurpleAccent),
                      _buildActionCard(
                          Icons.security, "Authenticate", authorize),
                      _buildActionCard(
                          Icons.data_usage, "Fetch Data", fetchData),
                    ],
                  ),
                  Divider(color: Colors.deepPurpleAccent),
                  _buildHealthDataDisplay(),
                  Divider(color: Colors.cyan),
                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(IconData icon, String text, VoidCallback onPressed) {
    return Card(
      color: Colors.grey[850],
      child: ListTile(
        dense: true,
        horizontalTitleGap: 0,
        leading: Icon(icon, color: Colors.deepPurpleAccent, size: 13),
        title: Text(text, style: TextStyle(color: Colors.white, fontSize: 12)),
        onTap: onPressed,
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  Widget _buildHealthDataDisplay() {
    switch (_state) {
      case AppState.FETCHING_DATA:
        return Center(child: CircularProgressIndicator());
      case AppState.DATA_READY:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: _healthDataList.map((dataPoint) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Card(
                color: Colors.grey[850],
                child: Column(
                  children: [
                    ListTile(
                      horizontalTitleGap: 0,
                      leading: Icon(
                        _getIconForDataType(dataPoint.type),
                        color: Colors.blue,
                        size: 13,
                      ),
                      title: Text(
                        '${(dataPoint.value as NumericHealthValue).numericValue} steps',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      subtitle: Text(
                        _formatDate(dataPoint.dateFrom),
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      onTap: () async {},
                    ),
                    _buildClaimRewardButton(_healthDataList.indexOf(dataPoint)),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      case AppState.NO_DATA:
        return ListTile(
          title: Text('No data available', style: TextStyle(color: Colors.white)),
          leading: Icon(Icons.error_outline, color: Colors.red),
        );
      default:
        return ListTile(
          title: Text('Press a button to get started',
              style: TextStyle(color: Colors.white)),
          leading: Icon(Icons.touch_app, color: Colors.grey),
        );
    }
  }

  Widget _buildClaimRewardButton(int index) {
    bool isLoading = _loadingIndex == index;
    bool isClaimed = _claimedRewards.contains(index);
    return TextButton(
      onPressed: () async {
        setState(() {
          _loadingIndex = index;
        });
        newFitCoinService = FitCoinService();
        await newFitCoinService.registerReward(
            "0xA412741a7f39E45E0baAAB9B7C8eEc6D700e2c2c",
            DateTime.now().millisecondsSinceEpoch.toString(),
            100000000000000000);
        double balance = await newFitCoinService
            .getBalance("0xA412741a7f39E45E0baAAB9B7C8eEc6D700e2c2c");
        setState(() {
          _balanceFitCoin = balance;
          _claimedRewards.add(index);
          _loadingIndex = null;

        });

        // stop loading
        setState(() {
          _loadingIndex = null;
        });
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isClaimed ? 'Reward Claimed' : 'Claim Reward',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          SizedBox(width: 5),
          isLoading
              ? SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.green,
            ),
          )
              : Icon(
            isClaimed ? Icons.check : Icons.monetization_on,
            color: isClaimed ? Colors.grey : Colors.green,
            size: 13,
          ),
        ],
      ),
    );
  }

  IconData _getIconForDataType(HealthDataType dataType) {
    switch (dataType) {
      case HealthDataType.STEPS:
        return Icons.directions_walk;
      case HealthDataType.WEIGHT:
        return Icons.monitor_weight;
      case HealthDataType.ACTIVE_ENERGY_BURNED:
        return Icons.local_fire_department;
      case HealthDataType.HEART_RATE:
        return Icons.favorite;
      case HealthDataType.BLOOD_GLUCOSE:
        return Icons.bloodtype;
      default:
        return Icons.health_and_safety;
    }
  }
}

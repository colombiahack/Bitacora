import 'package:flutter/material.dart';

import '../../pilot/presentation/profile_tab.dart';
import 'aircraft_tab.dart';
import 'battery_tab.dart';

/// "Hangar y Perfil": aeronaves, baterías y datos del piloto.
class HangarPage extends StatelessWidget {
  const HangarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Hangar y perfil'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.flight), text: 'Aeronaves'),
              Tab(icon: Icon(Icons.battery_charging_full), text: 'Baterías'),
              Tab(icon: Icon(Icons.badge_outlined), text: 'Piloto'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AircraftTab(),
            BatteryTab(),
            ProfileTab(),
          ],
        ),
      ),
    );
  }
}

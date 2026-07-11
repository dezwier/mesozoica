import 'package:flutter/material.dart';

import '../config/app_config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _checkingHealth = false;
  String _apiStatus = 'Not checked';

  Future<void> _checkHealth() async {
    setState(() {
      _checkingHealth = true;
      _apiStatus = 'Checking...';
    });

    final healthy = await AppConfig.checkApiHealth();
    if (!mounted) return;

    setState(() {
      _checkingHealth = false;
      _apiStatus = healthy ? 'API reachable' : 'API unreachable';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesozoica'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.landscape_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Mesozoica — scaffold',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Map, Lab, Museum, and Tree of Life screens will live here.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text('Backend: $_apiStatus'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _checkingHealth ? null : _checkHealth,
                icon: _checkingHealth
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: const Text('Check API health'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

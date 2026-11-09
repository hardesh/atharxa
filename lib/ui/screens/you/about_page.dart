import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_info.dart';
import '../../../state/core_providers.dart';
import '../../../state/sync_controller.dart';
import '../../theme/semantic.dart';
import '../../widgets/layout.dart';

/// You › About: version, where data lives and when the app goes online,
/// this device, credits and licences.
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceName = ref.watch(syncControllerProvider.select((s) => s.deviceName));
    final deviceId = ref.read(dbProvider).deviceId;
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: context.cs.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: context.tt.bodyMedium)),
        ],
      ),
    );
    return PageBody(
      children: [
        AppCard(
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(AppInfo.iconAsset, width: 64, height: 64, cacheWidth: 192),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppInfo.name, style: context.tt.titleLarge),
                    Text('Version ${AppInfo.version}', style: context.tt.bodySmall),
                    const SizedBox(height: 4),
                    Text('Food, water, workouts and money, on your own devices.', style: context.tt.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your data', style: context.tt.titleMedium),
              const SizedBox(height: 4),
              point(Icons.phone_android, 'Stored on this device in a local database. No account, no cloud.'),
              point(
                Icons.wifi,
                'Wi-Fi sync goes straight between your devices on the same network, signed with your pairing code.',
              ),
              point(
                Icons.auto_awesome_outlined,
                'The assistant runs on this device; nothing you ask it leaves the device.',
              ),
              point(
                Icons.public,
                'The app goes online only for Open Food Facts search, Strava, workout videos and AI model downloads.',
              ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This device', style: context.tt.titleMedium),
              const SizedBox(height: 4),
              Text(deviceName, style: context.tt.bodyLarge),
              Text('Device ID ${deviceId.substring(0, 8)}', style: context.tt.bodySmall),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Credits', style: context.tt.titleMedium),
              const SizedBox(height: 4),
              point(
                Icons.restaurant_outlined,
                'Food data from Open Food Facts (openfoodfacts.org), under the Open Database License (ODbL).',
              ),
              point(Icons.memory, 'Gemma 4 by Google and Qwen3.5 by Alibaba, under the Apache 2.0 licence.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: AppInfo.name,
                  applicationVersion: AppInfo.version,
                ),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Open-source licences'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

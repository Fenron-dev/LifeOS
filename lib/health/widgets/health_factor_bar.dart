import 'package:flutter/material.dart';

/// Segmented bar showing healthy/neutral/unhealthy share of logged meals.
/// [stats]: map from healthFactor (1/0/-1/null) to entry count.
class HealthFactorBar extends StatelessWidget {
  final Map<int?, int> stats;
  const HealthFactorBar({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final healthy = stats[1] ?? 0;
    final neutral = stats[0] ?? 0;
    final unhealthy = stats[-1] ?? 0;
    final total = healthy + neutral + unhealthy;
    if (total == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ernährungsqualität',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: [
              if (healthy > 0)
                Expanded(
                  flex: healthy,
                  child: Container(height: 10, color: Colors.green.shade400),
                ),
              if (neutral > 0)
                Expanded(
                  flex: neutral,
                  child: Container(height: 10, color: Colors.amber.shade400),
                ),
              if (unhealthy > 0)
                Expanded(
                  flex: unhealthy,
                  child: Container(height: 10, color: Colors.red.shade400),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (healthy > 0) ...[
              Text('😊 $healthy', style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 8),
            ],
            if (neutral > 0) ...[
              Text('😐 $neutral', style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 8),
            ],
            if (unhealthy > 0)
              Text('😞 $unhealthy', style: const TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/ean_validator.dart';

/// Vollbild-Kamerascanner. Gibt den ersten erkannten Barcode via [Navigator.pop] zurück.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _detected = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_detected) return;
    // Checksum-invalid EAN-8/13 reads are almost always camera misreads —
    // keep scanning instead of returning garbage (#3). Sync-pairing QR codes
    // (lifeos-sync://…) pass through for the settings pairing flow.
    final value = capture.barcodes.map((b) => b.rawValue).firstWhere(
        (v) =>
            v != null &&
            (isAcceptableEan(v) || v.startsWith('lifeos-sync://')),
        orElse: () => null);
    if (value == null) return;
    _detected = true;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Barcode scannen'),
        actions: [
          ValueListenableBuilder(
            valueListenable: _ctrl,
            builder: (_, state, child) {
              final torchOn = state.torchState == TorchState.on;
              return IconButton(
                icon: Icon(
                  torchOn ? Icons.flash_on : Icons.flash_off,
                  color: torchOn ? Colors.yellow : Colors.white,
                ),
                tooltip: torchOn ? 'Licht aus' : 'Licht an',
                onPressed: () => _ctrl.toggleTorch(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios_outlined, color: Colors.white),
            tooltip: 'Kamera wechseln',
            onPressed: () => _ctrl.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _ctrl, onDetect: _onDetect),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: cs.primary, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 96,
            left: 0,
            right: 0,
            child: Text(
              'Halte den Barcode in den Rahmen.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
                  ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context, ''),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                ),
                child: const Text('Kein Barcode – manuell eingeben'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

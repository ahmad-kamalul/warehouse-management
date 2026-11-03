import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// One accepted barcode per visit prevents duplicate camera frames becoming units.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan item SKU')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Scan a barcode containing the item SKU. You can confirm the quantity on the next screen.',
          ),
        ),
        Expanded(
          child: MobileScanner(
            // The widget owns its controller and handles pause/resume and disposal.
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Camera unavailable. Allow camera access in device settings, or go back and enter the SKU manually.',
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Use manual entry'),
                    ),
                  ],
                ),
              ),
            ),
            onDetect: (capture) {
              if (_accepted) return;
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue?.trim();
                if (value != null && value.isNotEmpty) {
                  _accepted = true;
                  Navigator.pop(context, value);
                  break;
                }
              }
            },
          ),
        ),
      ],
    ),
  );
}

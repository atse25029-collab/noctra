import 'package:flutter/material.dart';
import '../services/noctra_client.dart';

class ConnectionSheet extends StatefulWidget {
  final NoctraClient client;

  const ConnectionSheet({super.key, required this.client});

  static void show(BuildContext context, NoctraClient client) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ConnectionSheet(client: client),
    );
  }

  @override
  State<ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<ConnectionSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.client.host);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return ListenableBuilder(
      listenable: widget.client,
      builder: (context, _) {
        final status = widget.client.status;
        final isConnected = status == ConnectionStatus.connected;
        final isDiscovering = status == ConnectionStatus.discovering;

        return Container(
          padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
          decoration: BoxDecoration(
            color: const Color(0xFF14161F),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isConnected
                          ? const Color(0xFF22C55E)
                          : isDiscovering
                              ? const Color(0xFFEAB308)
                              : const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isConnected
                                  ? const Color(0xFF22C55E)
                                  : isDiscovering
                                      ? const Color(0xFFEAB308)
                                      : const Color(0xFFEF4444))
                              .withValues(alpha: 0.4),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isConnected
                        ? 'Connected to Noctra'
                        : isDiscovering
                            ? 'Searching on Wi-Fi...'
                            : 'Disconnected',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: isDiscovering
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.refresh_rounded, color: Colors.white70),
                    tooltip: 'Auto-discover PC',
                    onPressed: isDiscovering ? null : () => widget.client.discoverAndConnect(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Connect to Noctra running on your PC (same Wi-Fi network).',
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'Noctra PC IP Address',
                  labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  prefixIcon: const Icon(Icons.computer_rounded, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFF6B8AFD), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final ip = _controller.text.trim();
                  if (ip.isNotEmpty) {
                    widget.client.setHost(ip);
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6B8AFD),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('Save & Connect', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

class WishlistScreen extends StatelessWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '欲しいもの',
          style: TextStyle(
            color: colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: const Center(
        child: Text(
          'この機能は開発中です',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

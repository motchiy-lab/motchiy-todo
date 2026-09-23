import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class WishlistScreen extends StatelessWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        titleSpacing: 24,
        elevation: 0,
        title: Text(
          '欲しいもの',
          style: TextStyle(
            color: colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: isMobile
            ? null
            : [
                IconButton(
                  onPressed: () => _showRefreshMessage(context),
                  tooltip: '再読み込み',
                  icon: const Icon(Icons.refresh),
                ),
              ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _showRefreshMessage(context),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 500,
              child: Center(
                child: Text(
                  'この機能は開発中です',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRefreshMessage(BuildContext context) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('最新の状態です')));
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8000');

void main() => runApp(const AmirightApp());

class AmirightApp extends StatelessWidget {
  const AmirightApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AMRight',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const Scaffold(body: SafeArea(child: CoverageRanking(query: {'ward': 'URO', 'infection_type': 'uti'}))),
      );
}

/// Catalog widget: takes only query parameters and fetches its numbers from the API.
class CoverageRanking extends StatefulWidget {
  const CoverageRanking({super.key, required this.query, this.client});

  final Map<String, String> query;
  final http.Client? client;

  @override
  State<CoverageRanking> createState() => _CoverageRankingState();
}

class _CoverageRankingState extends State<CoverageRanking> {
  late final Future<Map<String, dynamic>> _data = _fetch();

  Future<Map<String, dynamic>> _fetch() async {
    final uri = Uri.parse('$apiBase/v1/coverage').replace(queryParameters: widget.query);
    final res = await (widget.client ?? http.Client()).get(uri);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Could not load coverage: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return _CoverageView(data: snap.data!);
        },
      );
}

class _CoverageView extends StatelessWidget {
  const _CoverageView({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final recent = data['recent'] as Map<String, dynamic>;
    final annual = data['annual'] as Map<String, dynamic>;
    final annualByRegimen = {
      for (final o in annual['options'] as List) (o['regimen'] as List).join('+'): o as Map<String, dynamic>,
    };
    final narrowest = (recent['narrowest_effective'] as List?)?.join('+');
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Coverage ${data['ward']} · ${data['specimen']}', style: Theme.of(context).textTheme.headlineSmall),
      if (data['note'] != null) Text(data['note'] as String),
      const SizedBox(height: 8),
      Text('Last 28 days (n=${recent['n_first_isolates']}) next to 12 months (n=${annual['n_first_isolates']})'),
      if (narrowest != null) Chip(label: Text('Narrowest effective: $narrowest')),
      const Divider(),
      for (final o in recent['options'] as List)
        _Row(option: o as Map<String, dynamic>, annual: annualByRegimen[(o['regimen'] as List).join('+')]),
    ]);
  }
}

String _pct(num v) => '${(v * 100).round()}%';

class _Row extends StatelessWidget {
  const _Row({required this.option, this.annual});

  final Map<String, dynamic> option;
  final Map<String, dynamic>? annual;

  @override
  Widget build(BuildContext context) {
    final c = option['coverage'] as Map<String, dynamic>;
    final a = annual?['coverage'] as Map<String, dynamic>?;
    return ListTile(
      title: Text((option['regimen'] as List).join(' + ')),
      subtitle: Text(
        '28d ${_pct(c['value'])} (${_pct(c['low'])}–${_pct(c['high'])}), n=${c['n']}, '
        '${_pct(c['prior_weight'])} from the ${c['prior_level']} prior'
        '${a == null ? '' : ' · 12mo ${_pct(a['value'])}'}',
      ),
      trailing: option['covers_target'] == true ? const Icon(Icons.check_circle, color: Colors.green) : null,
    );
  }
}

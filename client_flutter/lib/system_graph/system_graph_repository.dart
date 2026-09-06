import 'dart:convert';

import 'package:flutter/services.dart';

import 'system_graph_document.dart';

abstract interface class SystemGraphRepository {
  Future<SystemGraphDocument> load();
}

class AssetSystemGraphRepository implements SystemGraphRepository {
  const AssetSystemGraphRepository();

  static const assetPath = 'assets/system_graph/flowspace_system_graph.json';

  @override
  Future<SystemGraphDocument> load() async {
    final data = await rootBundle.load(assetPath);
    final source = utf8.decode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    return SystemGraphDocument.fromJsonString(source);
  }
}

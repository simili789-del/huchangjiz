import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../../domain/entities/monthly_report.dart';
import '../../domain/entities/ocr_result.dart';
import 'ocr_engine.dart';
import 'secure_settings_repository.dart';

/// 阿里云通义千问 Qwen-VL 云端 OCR 引擎。
///
/// 核心思路：让视觉大模型直接吐结构化 JSON 月度作业量汇总表，
/// 绕过行级 OCR + 网格解析器，从源头消除"字符错 + 空间错位"两层错误。
///
/// 流程：图像预处理（与离线共用）→ 长边压到 2048px → base64 → POST DashScope
///      → JSON 模式解析 → 直接构造 [MonthlyReport]。
class QwenVlOcrEngine implements OcrEngine {
  QwenVlOcrEngine({
    required this.apiKey,
    this.baseUrl = SecureSettingsRepository.defaultBaseUrl,
    this.model = SecureSettingsRepository.defaultModel,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String baseUrl;
  final String model;
  final http.Client _client;

  /// 单次请求超时：Qwen-VL 大表需 10~20s，给 60s 留余量。
  static const _timeout = Duration(seconds: 60);

  @override
  Future<List<OcrLine>> recognize(String imagePath) async {
    // 老接口：返回合成 OcrLine 仅用于"云端直出但上层要走行级预览"回退场景。
    // 主要准确率路径走 [recognizeStructured]。
    final report = await recognizeStructured(imagePath);
    if (report == null) return const [];
    return _reportToSyntheticLines(report);
  }

  /// 云端直出结构化月报。失败/未配 key → 返回 null，由上层降级离线。
  @override
  Future<MonthlyReport?> recognizeStructured(String imagePath) async {
    if (apiKey.isEmpty) return null;

    final bytes = await _loadAndCompress(imagePath);
    final base64Img = base64Encode(bytes);

    final prompt = _buildPrompt();
    final body = jsonEncode({
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$base64Img'}},
            {'type': 'text', 'text': prompt},
          ],
        },
      ],
      'response_format': {'type': 'json_object'},
      'temperature': 0.0,
      'max_tokens': 8000,
    });

    final resp = await _client
        .post(
          Uri.parse(baseUrl),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(_timeout);

    if (resp.statusCode != 200) {
      throw QwenVlException(
        'DashScope 返回 ${resp.statusCode}: ${_truncate(resp.body, 200)}',
        statusCode: resp.statusCode,
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = _extractContent(data);
    if (content == null) {
      throw const QwenVlException('DashScope 响应无 content 字段');
    }

    return _parseReport(content);
  }

  /// 轻量连通性测试：发最小 payload 验证 key 有效。
  Future<bool> testConnection() async {
    if (apiKey.isEmpty) return false;
    try {
      // 1x1 透明 PNG
      const tinyPng =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
      final body = jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,$tinyPng'}},
              {'type': 'text', 'text': '输出 {"ok": true}'},
            ],
          },
        ],
        'response_format': {'type': 'json_object'},
        'max_tokens': 16,
      });
      final resp = await _client
          .post(
            Uri.parse(baseUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 15));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---- 私有 ----

  Future<Uint8List> _loadAndCompress(String imagePath) async {
    final raw = await File(imagePath).readAsBytes();
    // 长边压到 2048px：减少 base64 体积与 token 消耗。2k 足够看清表格。
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return raw;
      final w = decoded.width;
      final h = decoded.height;
      final longSide = w > h ? w : h;
      if (longSide <= 2048) return raw;
      final scale = 2048 / longSide;
      final resized = img.copyResize(decoded,
          width: (w * scale).round(), height: (h * scale).round());
      return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
    } catch (_) {
      return raw;
    }
  }

  String _buildPrompt() => '''
你是一名严谨的 OCR 专员。图中是一张「货场月度作业量汇总表」。
请把所有内容按以下 JSON Schema 严格输出，不要任何解释文字、不要 markdown 围栏：

{
  "year": 2026,
  "month": 8,
  "employees": [
    {
      "name": "王应周",
      "overtimeDates": [],
      "prices": [
        {
          "price": 1.2,
          "days": [
            {"day": 1, "dayShift": "早", "value": 5},
            {"day": 1, "dayShift": "晚", "value": 0}
          ]
        }
      ]
    }
  ]
}

规则：
1. 表头跨多列：日期(1~31) × 班次(早/晚)，每个员工名后接 N 个「X元/车」单价行；N 由该员工实际有的单价档次决定
2. 空白单元格 value=0，不要省略任何 day×dayShift 组合
3. 紫底/红底单元格视为正常数据；如该日某班次明确写"加班""加"等字样，把对应 day 加入该员工的 overtimeDates 数组
4. 数字读不清就 0，宁可漏不可猜
5. price 严格保留一位小数（如 1.2 / 1.8 / 5.0）
6. JSON 必须完整闭合，最后不要加任何标点
''';

  String? _extractContent(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first as Map<String, dynamic>;
    final msg = first['message'];
    if (msg is Map<String, dynamic>) {
      final c = msg['content'];
      if (c is String) return c;
    }
    return null;
  }

  /// 解析 Qwen-VL 吐的 JSON 文本（可能夹带 markdown 围栏）→ MonthlyReport。
  MonthlyReport? _parseReport(String content) {
    try {
      var raw = content.trim();
      // 容错：去掉 ```json ... ``` 围栏
      if (raw.startsWith('```')) {
        final newline = raw.indexOf('\n');
        if (newline > 0) raw = raw.substring(newline + 1);
        if (raw.endsWith('```')) raw = raw.substring(0, raw.length - 3);
        raw = raw.trim();
      }
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final year = (j['year'] as num?)?.toInt() ?? DateTime.now().year;
      final month = (j['month'] as num?)?.toInt() ?? DateTime.now().month;
      final emps = (j['employees'] as List?) ?? const [];

      final entries = <ReportEntry>[];
      for (final e in emps) {
        if (e is! Map) continue;
        final name = (e['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final prices = (e['prices'] as List?) ?? const [];
        if (prices.isEmpty) continue;

        // 同一员工可能有多个单价档次：每个 price 一条 ReportEntry。
        for (final p in prices) {
          if (p is! Map) continue;
          final price = (p['price'] as num?)?.toDouble() ?? 0;
          final days = (p['days'] as List?) ?? const [];
          final cells = <ReportCell>[];
          for (final d in days) {
            if (d is! Map) continue;
            final day = (d['day'] as num?)?.toInt() ?? 0;
            final shift = (d['dayShift'] as String?)?.trim() ?? '早';
            final value = (d['value'] as num?)?.toInt() ?? 0;
            if (day < 1 || day > 31) continue;
            cells.add(ReportCell(day: day, shift: shift, count: value));
          }
          final total = cells.fold<int>(0, (s, c) => s + c.count);
          entries.add(ReportEntry(
            workerName: name,
            price: price,
            cells: cells,
            total: total,
          ));
        }
      }

      if (entries.isEmpty) return null;
      return MonthlyReport(year: year, month: month, entries: entries);
    } catch (e, st) {
      debugPrint('QwenVlOcrEngine._parseReport 失败: $e\n$st');
      return null;
    }
  }

  /// 把结构化月报"反向"合成 OcrLine（仅用于老接口预览，非主路径）。
  List<OcrLine> _reportToSyntheticLines(MonthlyReport report) {
    final out = <OcrLine>[];
    for (final e in report.entries) {
      out.add(OcrLine(text: e.workerName));
      out.add(OcrLine(text: '${_fmtPrice(e.price)}元/车'));
      for (final c in e.cells) {
        if (c.count > 0) {
          out.add(OcrLine(text: '${c.day} ${c.shift} ${c.count}'));
        }
      }
    }
    return out;
  }

  String _fmtPrice(double p) =>
      p == p.roundToDouble() ? p.toInt().toString() : p.toString();

  String _truncate(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n)}…';

  @override
  void dispose() => _client.close();
}

class QwenVlException implements Exception {
  final String message;
  final int? statusCode;
  const QwenVlException(this.message, {this.statusCode});
  @override
  String toString() => 'QwenVlException($statusCode): $message';
}

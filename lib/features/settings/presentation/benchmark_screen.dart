import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../chat/models/chat_message.dart';
import '../../chat/service/local_ai_service.dart';

/// Holds measured results from a standardized on-device benchmark run.
class BenchmarkResult {
  final String modelName;
  final String modelSize;
  final int contextSize;
  final int threads;
  final int ttftMs;
  final int totalDurationMs;
  final int estimatedTokens;
  final int wordCount;
  final int? modelLoadTimeMs;

  const BenchmarkResult({
    required this.modelName,
    required this.modelSize,
    required this.contextSize,
    required this.threads,
    required this.ttftMs,
    required this.totalDurationMs,
    required this.estimatedTokens,
    required this.wordCount,
    this.modelLoadTimeMs,
  });

  double get tokensPerSecond {
    final seconds = totalDurationMs / 1000.0;
    if (seconds <= 0) return 0;
    return estimatedTokens / seconds;
  }

  double get wordsPerSecond {
    final seconds = totalDurationMs / 1000.0;
    if (seconds <= 0) return 0;
    return wordCount / seconds;
  }

  String get ratingLabel {
    final tps = tokensPerSecond;
    if (tps >= 15.0) return 'Blazing Fast';
    if (tps >= 8.0) return 'Smooth';
    if (tps >= 4.0) return 'Moderate';
    return 'Lightweight Model Recommended';
  }

  Color get ratingColor {
    final tps = tokensPerSecond;
    if (tps >= 15.0) return const Color(0xFF10B981);
    if (tps >= 8.0) return const Color(0xFF6366F1);
    if (tps >= 4.0) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  /// Generates a clean Markdown summary aligned with `docs/BENCHMARKS.md`.
  String toMarkdownReport() {
    final loadStr = modelLoadTimeMs != null
        ? '${(modelLoadTimeMs! / 1000).toStringAsFixed(2)}s'
        : 'N/A';
    return '''
### Arivu AI On-Device Benchmark Report
| Metric | Measured Value |
| :--- | :--- |
| **Model** | $modelName ($modelSize) |
| **Config** | $threads CPU threads • $contextSize context |
| **Generation Speed** | **${tokensPerSecond.toStringAsFixed(1)} tok/s** (${wordsPerSecond.toStringAsFixed(1)} words/s) |
| **Time to First Token (TTFT)** | ${ttftMs}ms |
| **Model Load Time** | $loadStr |
| **Total Output** | ~$estimatedTokens tokens ($wordCount words) in ${(totalDurationMs / 1000).toStringAsFixed(2)}s |
| **Device Rating** | $ratingLabel |
''';
  }
}

/// Dedicated In-App "Benchmark My Phone" Diagnostics Screen.
class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key, required this.aiService});

  final LocalAiService aiService;

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  static const String _standardPrompt =
      'Explain how photosynthesis works in plants in 3 concise bullet points.';

  bool _isRunning = false;
  bool _isCancelled = false;
  String _liveOutput = '';
  BenchmarkResult? _result;
  String? _error;

  Future<void> _runBenchmark() async {
    if (_isRunning) return;

    if (!widget.aiService.isLoaded) {
      setState(() {
        _error = 'No model is currently loaded. Please load a model first.';
      });
      return;
    }

    setState(() {
      _isRunning = true;
      _isCancelled = false;
      _liveOutput = '';
      _result = null;
      _error = null;
    });

    final stopwatch = Stopwatch()..start();
    int? ttftMs;
    final buffer = StringBuffer();

    try {
      final stream = widget.aiService.askStream(
        [
          ChatMessage(
            conversationId: -1,
            role: 'user',
            content: _standardPrompt,
            createdAt: DateTime.now(),
          ),
        ],
        maxTokens: 120,
        temperature: 0.1,
      );

      await for (final chunk in stream) {
        if (_isCancelled || !mounted) break;
        ttftMs ??= stopwatch.elapsedMilliseconds;
        buffer.write(chunk);
        setState(() {
          _liveOutput = buffer.toString();
        });
      }

      stopwatch.stop();
      if (!mounted) return;

      final finalOutput = buffer.toString().trim();
      final words = finalOutput.isEmpty
          ? 0
          : finalOutput.split(RegExp(r'\s+')).length;
      final approxTokens = (finalOutput.length / 4).ceil();
      final model = widget.aiService.activeModel;
      final config = widget.aiService.inferenceConfig;

      setState(() {
        _result = BenchmarkResult(
          modelName: model.name,
          modelSize: model.sizeFormatted,
          contextSize: config.contextSize,
          threads: config.numberOfThreads,
          ttftMs: ttftMs ?? stopwatch.elapsedMilliseconds,
          totalDurationMs: stopwatch.elapsedMilliseconds,
          estimatedTokens: approxTokens,
          wordCount: words,
          modelLoadTimeMs: widget.aiService.performanceMetrics?.modelLoadTimeMs,
        );
      });
    } catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _error = 'Benchmark interrupted: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  void _stopBenchmark() {
    if (_isRunning) {
      setState(() => _isCancelled = true);
    }
  }

  void _copyReport() {
    if (_result == null) return;
    Clipboard.setData(ClipboardData(text: _result!.toMarkdownReport()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Benchmark Markdown report copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final model = widget.aiService.activeModel;
    final config = widget.aiService.inferenceConfig;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A0F1E) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        elevation: 0.5,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Benchmark My Phone',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'Offline On-Device Speed Diagnostics',
              style: TextStyle(fontSize: 12, color: Color(0xFF10B981)),
            ),
          ],
        ),
        actions: [
          if (_result != null)
            IconButton(
              tooltip: 'Copy Markdown report',
              onPressed: _copyReport,
              icon: const Icon(Icons.copy_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Active Model & Hardware Config Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131B2E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.speed_rounded,
                        color: Color(0xFF4F46E5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            model.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${model.sizeFormatted} • ${config.numberOfThreads} CPU Threads • ${config.contextSize} Context',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _isRunning
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF4F46E5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isRunning ? _stopBenchmark : _runBenchmark,
                    icon: Icon(
                      _isRunning
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(
                      _isRunning
                          ? 'Stop Benchmark'
                          : (_result == null
                              ? 'Run Standardized Benchmark'
                              : 'Re-run Benchmark'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
              ),
            ),
          ],

          if (_result != null) ...[
            const SizedBox(height: 18),
            // Performance Rating Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _result!.ratingColor.withValues(alpha: isDark ? 0.18 : 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _result!.ratingColor.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_rounded, color: _result!.ratingColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Device Rating: ${_result!.ratingLabel}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        color: _result!.ratingColor,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _copyReport,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy Report'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Metric Tiles Grid
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.55,
              children: [
                _buildMetricCard(
                  isDark: isDark,
                  icon: Icons.bolt_rounded,
                  color: const Color(0xFF10B981),
                  label: 'Generation Speed',
                  value: '${_result!.tokensPerSecond.toStringAsFixed(1)} tok/s',
                  sub: '${_result!.wordsPerSecond.toStringAsFixed(1)} words/s',
                ),
                _buildMetricCard(
                  isDark: isDark,
                  icon: Icons.timer_outlined,
                  color: const Color(0xFF6366F1),
                  label: 'First Token (TTFT)',
                  value: '${_result!.ttftMs} ms',
                  sub: 'Prompt prefill latency',
                ),
                _buildMetricCard(
                  isDark: isDark,
                  icon: Icons.memory_rounded,
                  color: const Color(0xFFF59E0B),
                  label: 'Model Load Time',
                  value: _result!.modelLoadTimeMs != null
                      ? '${(_result!.modelLoadTimeMs! / 1000).toStringAsFixed(2)} s'
                      : 'N/A',
                  sub: 'Native GGUF load',
                ),
                _buildMetricCard(
                  isDark: isDark,
                  icon: Icons.analytics_outlined,
                  color: const Color(0xFFEC4899),
                  label: 'Total Generated',
                  value: '~${_result!.estimatedTokens} tok',
                  sub:
                      'in ${(_result!.totalDurationMs / 1000).toStringAsFixed(2)} s',
                ),
              ],
            ),
          ],

          if (_isRunning || _liveOutput.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              _isRunning ? 'Live Streaming Output...' : 'Benchmark Sample Output',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131B2E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Text(
                _liveOutput.isEmpty ? 'Warming up KV cache...' : _liveOutput,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: isDark
                      ? const Color(0xFFE2E8F0)
                      : const Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required bool isDark,
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131B2E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: isDark
                  ? const Color(0xFF64748B)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

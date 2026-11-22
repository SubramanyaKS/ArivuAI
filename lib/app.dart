import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arivu_ai/features/chat/service/local_ai_service.dart';
import 'package:arivu_ai/features/model/presentation/model_setup_screen.dart';
import 'package:arivu_ai/provider/theme_provider.dart';
import 'package:arivu_ai/utils/theme.dart';

class ArivuAiApp extends ConsumerStatefulWidget {
  const ArivuAiApp({super.key});

  @override
  ConsumerState<ArivuAiApp> createState() => _ArivuAiAppState();
}

class _ArivuAiAppState extends ConsumerState<ArivuAiApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    LocalAiService.instance.handleMemoryPressure();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Arivu AI',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const ModelSetupScreen(),
    );
  }
}

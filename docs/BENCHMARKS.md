# Arivu AI — On-Device Model Benchmarks & Hardware Guide

This document provides empirical performance metrics, memory footprints, and hardware recommendations for the quantized GGUF models supported in **Arivu AI (ಅರಿವು AI)**.

All benchmarks are measured using on-device mobile CPU inference (`llamadart` / `llama.cpp`) with default settings:
- **CPU Threads**: 4 threads
- **Context Size**: 2,048 tokens
- **Inference Mode**: Profile / Release build (`flutter run --profile`)

---

## 1. Summary Benchmark Matrix

| Model Specification | Quantization | Disk File Size | Active Model RAM (PSS) | TTFT (Time-to-First-Token) | Throughput (Mid-Range: SD 778G / Dimensity 7050) | Throughput (Flagship: Snapdragon 8 Gen 2/3) | Primary Strengths |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **SmolLM2 360M Instruct** | `Q8_0` | ~386 MB | ~450 MB | **~240–350 ms** | **16–20 words/s** (~22–27 t/s) | **26–32 words/s** (~35–43 t/s) | Ultra-fast voice replies, minimal battery draw, budget phones (2–3 GB RAM). |
| **Qwen2.5 0.5B Instruct** | `Q8_0` | ~524 MB | ~620 MB | **~320–480 ms** | **12–16 words/s** (~16–21 t/s) | **20–26 words/s** (~27–35 t/s) | Compact general assistant with strong multilingual and structured formatting. |
| **Qwen3 0.6B Q8_0 (Default)** | `Q8_0` | ~639 MB | ~740 MB | **~380–520 ms** | **9–13 words/s** (~12–17 t/s) | **16–22 words/s** (~21–29 t/s) | Best balanced daily driver, reasoning flow, and device tool execution. |
| **SmolLM2 1.7B Instruct** | `Q4_K_M` | ~1.05 GB | ~1,250 MB | **~650–850 ms** | **5–7 words/s** (~7–10 t/s) | **9–13 words/s** (~12–17 t/s) | High comprehension edge model, long explanations, compact 4-bit size. |
| **Qwen2.5 1.5B Instruct** | `Q4_K_M` | ~1.03 GB | ~1,380 MB | **~680–920 ms** | **4–7 words/s** (~6–9 t/s) | **8–12 words/s** (~11–16 t/s) | Complex logic, coding, deep document synthesis (RAG), 6–8 GB+ RAM. |

> [!NOTE]
> In typical English language tokenization, **1 word ≈ 1.33 tokens** (or ~4 characters per token). Throughput figures above list both visible words per second and equivalent token throughput.

---

## 2. Hardware Compatibility & RAM Recommendations

Mobile devices enforce strict per-app RAM boundaries (Android LMK — Low Memory Killer). Choose the model that matches your phone's total system memory:

```
+------------------------------------------------------------------------+
| TOTAL PHONE RAM    RECOMMENDED MODELS                     NOTES         |
+------------------------------------------------------------------------+
| 2 GB - 3 GB       SmolLM2-360M                           Safe baseline |
| 4 GB - 6 GB       Qwen3-0.6B (Default) or Qwen2.5-0.5B   Recommended   |
| 6 GB - 8 GB+      Qwen2.5-1.5B or SmolLM2-1.7B           High IQ / Code|
+------------------------------------------------------------------------+
```

- **For 2 GB – 3 GB RAM Devices**: We strongly advise using **SmolLM2-360M**. Its ~450 MB resident memory footprint ensures the Android OS will not terminate background apps or kill the inference process.
- **For 4 GB – 6 GB RAM Devices**: The default **Qwen3-0.6B** (~740 MB RAM) delivers the best balance of reasoning and speed.
- **For 8 GB+ RAM Devices**: **Qwen2.5-1.5B** excels at detailed code generation, mathematical reasoning, and document question-answering across attached PDFs.

---

## 3. Standardized Testing Protocol

To benchmark models on your own device and reproduce these numbers, use the following standardized protocol:

### A. Test Prompts

Run three prompt tiers to measure different operational profiles:

1. **Short Prompt (Voice & Quick Queries — ~20 words target)**:
   > *"What is gravity and who discovered the law of universal gravitation?"*
   - *Measures*: Time-to-First-Token (TTFT) and latency before speech playback begins.
2. **Medium Prompt (Explanatory Dialogue — ~100 words target)**:
   > *"Explain how photosynthesis works in green plants step by step."*
   - *Measures*: Sustained generation throughput and coherent sentence boundary streaming.
3. **Long Prompt (Coding & Structured Reasoning — ~200 words target)**:
   > *"Write a clean Dart function to check if a string is a palindrome with comments and an explanation."*
   - *Measures*: Deep context handling, code block rendering speed, and peak RAM under sustained load.

---

## 4. How to Test and Measure on Your Device

### Step 1: Run in Profile or Release Mode
Always benchmark in `--profile` or `--release` mode. Debug mode runs Dart in an unoptimized JIT VM with assertions that inflate latency by 2x–3x:

```bash
flutter run --profile
```

### Step 2: Read Live Logs from Terminal
Arivu AI automatically tracks and logs generation telemetry in [`LocalAiService`](../lib/features/chat/service/local_ai_service.dart#L528-L547). When generation finishes, check your console or `adb logcat`:

```text
[PERF] Native model load: 1.34 s
[PERF] TTFT: 395 ms
[PERF] Total generation time: 4.20 s
[PERF] Visible characters: 412
[PERF] Visible words (approx): 82
[PERF] Visible output speed: 19.52 words/s
[PERF] Character throughput: 98.10 chars/s
```

### Step 3: Measure Exact RAM Usage with ADB
With your Android device connected via USB debugging, execute:

```bash
adb shell dumpsys meminfo com.subramanya.arivu_ai
```

Locate the **`TOTAL PSS`** row in the output to see the exact memory (in kilobytes) consumed by the Flutter engine and the native `llama.cpp` model weights.

---

## 5. Tuning Inference Parameters for Maximum Speed

You can customize performance live inside **Settings ➔ Inference Parameters**:

- **CPU Threads (1 to 8)**: 
  - On most modern octa-core processors (4 performance cores + 4 efficiency cores), setting **4 threads** provides the optimal balance of speed without thermal throttling.
  - Setting threads higher than physical performance cores (e.g. 8 threads on a 4-performance-core chip) can cause context-switching overhead and battery drain.
- **Context Window (1,024 vs 2,048 vs 4,096 tokens)**:
  - **1,024 (Eco)**: Conserves ~150–250 MB of RAM; ideal for older devices.
  - **2,048 (Default)**: Balanced for standard conversation and multi-turn chat.
  - **4,096 (Deep)**: Needed when attaching large PDFs and documents for local RAG.

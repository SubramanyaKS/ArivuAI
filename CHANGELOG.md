# Changelog

All notable changes to the **Arivu AI** (ಅರಿವು AI) project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.2.0] - 2026-11-21

### Added
- **Dedicated Document Intelligence Workspace**:
  - Added persistent offline **Knowledge Shelf** (`DocumentIntelligenceScreen`) backed by SQLite schema v4 (`documents` table with `idx_documents_created`).
  - Added 2-tab **Document Workspace** (`DocumentWorkspaceScreen`) featuring an **Ask Arivu** RAG Q&A tab and a **Document Viewer** tab with live offline keyword search.
  - Added one-tap specialized AI document workflows: *Executive Summary*, *Key Takeaways*, *Generate Q&A*, and *Action Items*.
  - Added interactive **tappable source citation chips** (`Source: Excerpt N`) below AI answers opening a verbatim preview bottom sheet.
  - Integrated direct navigation shortcuts in the `ChatScreen` AppBar and Drawer.

- **Two-Tier Hybrid Tool Calling Engine**:
  - Added `NlpNormalizer` (`lib/tools/nlp_normalizer.dart`) converting written number words, colloquial durations (*"half an hour"*, *"an hour and a half"*), and relative clock times (*"half past six"*, *"quarter to eight"*) for `<1ms` Tier 1 Fast-Path matching.
  - Added `ToolCallParser` (`lib/tools/tool_call_parser.dart`) supporting `<tool_call>` XML blocks, Markdown fences, raw JSON, and lenient auto-repair for small model formatting quirks.
  - Added `executeWithArgs` structured argument execution across all 8 `PocketTool` implementations and Tier 2 local LLM fallback in `ToolRegistry.dispatch` and `LocalAiService.askOnce`.

- **Full Offline Reminder Management**:
  - Upgraded `ReminderTool` and `NotificationService` to support **listing upcoming reminders** with relative time formatting (*"give me the list of reminders"*), **cancelling specific reminders** by title or number (*"cancel reminder to drink water"*), and **cancelling all reminders** (*"cancel all reminders"*).
  - Automatically marks expired past reminders as completed in SQLite and added cross-platform safety guards for unit testing.

- **Chat Ergonomics & SQLite Indexing**:
  - Added intelligent **Streaming Auto-Scroll** and an interactive **Stop Generation** button during token streaming.
  - Added **Regenerate Response** for the latest assistant reply and **Edit Prompt** for user messages with automatic downstream SQLite history truncation (`deleteMessage`, `deleteMessagesFrom`).
  - Added SQLite B-tree database indexing (schema v3) across `messages`, `conversations`, and `reminders`.

---

## [1.0.0] - 2026-11-10

### Added
- **Core On-Device AI Engine**:
  - Embedded `llama.cpp` machine learning runtime via `llamadart` executing quantized GGUF language models directly on mobile CPU with zero cloud dependencies.
  - Decoupled single-source-of-truth model catalog ([`assets/models/model_catalog.json`](assets/models/model_catalog.json)) supporting 5 open-weight models:
    - *SmolLM2 360M Instruct* (386 MB, Ultra-Fast & Voice)
    - *SmolLM2 1.7B Instruct* (1.05 GB, 4-bit Edge Intelligence)
    - *Qwen2.5 0.5B Instruct* (524 MB, Compact & Multilingual)
    - *Qwen3 0.6B Q8_0* (639 MB, Default boot model)
    - *Qwen2.5 1.5B Instruct* (1.03 GB, High Intelligence & Code)
  - Supply-chain security verification with GGUF binary magic header check (`0x47, 0x47, 0x55, 0x46`) and streaming SHA-256 cryptographic digest matching.
  - Multi-model storage manager with on-device hot-swapping and one-tap inactive model deletion in Settings to reclaim phone storage.

- **Inference Parameter Tuning in Settings**:
  - Configurable CPU generation threads (`1`, `2`, `4`, `6`, `8`) with dynamic live reload on active models without app restart.
  - Continuous sampling temperature slider (`0.0`–`1.0`) with real-time semantic badges (*Strict*, *Balanced*, *Creative*).
  - Context window size selection chips (`1K Eco`, `2K Default`, `4K Deep`).
  - Max generation token caps (`128`, `256`, `512`, `1024`).
  - Persistent storage in `inference_config.json` and a one-tap *Reset Defaults* action.

- **Full-Duplex Conversational Voice Assistant**:
  - Sentence-by-sentence streaming audio playback queue with delimiter-based buffering (`.`, `?`, `!`, `\n`) minimizing voice latency to `<1.5s`.
  - Auto-continuous hands-free dialogue loop with automatic microphone reactivation, silence timeout, and voice exit commands (*"stop"*, *"exit"*, *"quit"*).
  - Tap-to-interrupt (barge-in) instantly terminating audio playback and switching back to speech listening.
  - Live audio visualizer featuring 24-band animated waveform bars and responsive glowing orb dynamically scaled by real-time microphone RMS volume via `onSoundLevelChange` with exponential smoothing.
  - Enforced on-device speech recognition (`onDevice: true`).

- **Central Tool Registry & Deterministic Offline Tools**:
  - Central dispatcher `ToolRegistry` and extensible `PocketTool` contract executing device commands in `<1ms` without LLM latency or hallucination.
  - Native Android Clock alarms and countdown timers via `android_intent_plus` intents (`ACTION_SET_ALARM`, `ACTION_SET_TIMER`, `ACTION_DISMISS_ALARM`).
  - Exact scheduled reminders with `flutter_local_notifications` and timezone support, persisted to internal SQLite.
  - Deterministic offline arithmetic calculator with recursive descent parser evaluating PEMDAS operations, floating points, percentages, powers, and roots.
  - Application launcher for common Android apps (Camera, YouTube, Maps, WhatsApp, Chrome, Gallery, Email, Dialer, Messages, Spotify).
  - System settings shortcuts (Wi-Fi, Bluetooth, Display, Sound, Battery, Location, Airplane Mode).
  - Hardware camera flashlight control via `torch_light` and live battery diagnostics via `battery_plus`.

- **Offline Document Chat (Local RAG)**:
  - Local document ingestion supporting `.pdf`, `.txt`, and `.md` attachments directly in chat.
  - Pure Dart PDF text extraction via `syncfusion_flutter_pdf` with zero cloud or OS PDF dependencies.
  - Overlapping semantic boundary chunking (~600 chars with 80-char overlap).
  - Fast in-memory BM25 relevance retrieval (<2ms) with English stopword filtering.
  - Grounded anti-hallucination system prompt injection with interactive attachment chip displaying name, size, and chunk count.

- **Conversation Search & Chat Export**:
  - Full-text keyword search across chat titles and message history in the drawer with live query filtering and matching snippet previews.
  - Formatted Markdown (`.md`) transcript generation via `ChatExportService`.
  - Native Android share sheet integration (`share_plus`) and one-tap clipboard copy.

- **Zero-Cloud Privacy & Security**:
  - Sandboxed local SQLite database (`chat_history.db`) in private internal storage.
  - `android:allowBackup="false"` in `AndroidManifest.xml` preventing automated cloud extraction.
  - One-tap permanent *Wipe All Chat History* in Settings.
  - Zero telemetry, analytics SDKs, or ad tracking.

- **Licensing & Legal**:
  - Apache License, Version 2.0 with a 4-part Supplemental AI & Hardware Safety Addendum covering AI hallucination disclaimers, hardware automation actions, third-party model weights, and air-gapped security.

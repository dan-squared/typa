# <img src="Resources/typa%20logo.png" width="48" align="center" /> Typa

Typa is a macOS typing trainer focused on adaptive practice, local-first progress tracking, and a calmer visual rhythm than typical speed-test apps.

It combines two workflows:

- `Learning` mode continuously analyzes weak keys, transitions, corrections, and confidence to generate the next lesson.
- `Test` mode gives you fixed practice runs for common words, code words, numbers, or custom text.

The app is written in SwiftUI for macOS and uses SwiftData for local history persistence.

## Highlights

- Adaptive lesson generation based on the keys and transitions you actually miss
- Local-only history, settings, and profile data
- Detailed per-session telemetry including key stats, digraph misses, corrections, and timing
- Multiple keyboard layouts including QWERTY, QWERTY UK, Colemak, and Dvorak
- Practice sources for common words, code words, number groups, and custom libraries
- Visual customization for font size, line height, spacing, caret style, colors, and background noise
- Optional sound packs and error sounds
- A profile dashboard for progress, milestones, streaks, and recent adaptive trends

## App Structure

At a high level, Typa is organized into a few major areas:

- `TypaApp.swift`
  Scene setup, primary window lifecycle, settings scene, and app bootstrap.
- `TypingView.swift`
  The main practice experience, session flow, result presentation, and live overlays.
- `SettingsView.swift`
  Practice, learning, appearance, audio/data, and custom snippet configuration.
- `Swift/AdaptiveTypingEngine.swift`
  Adaptive telemetry, lesson state, normalization, and payload encoding/decoding.
- `Models/AdaptiveTrainingProfile.swift`
  Training profile snapshots, key details, streaks, goal progress, and event generation.
- `Swift/AdaptiveAnalysisView.swift`
  Profile and progress analysis UI.
- `Models/HistoryTransfer.swift`, `Models/HistoryImportPipeline.swift`, `Models/TypingResult.swift`
  History persistence and transfer/import support.
- `Views/`
  Shared UI pieces such as the floating stats badge and caret.
- `Resources/`
  Word corpora, keyboard audio assets, and language data files.

## How The Engine Works

Typa’s adaptive system is not just a random lesson picker. It builds structured telemetry from every session and uses that telemetry to decide what to practice next.

### 1. Session Capture

During a typing session, Typa records:

- accepted inputs
- rejected inputs
- corrected inputs
- cursor position over time
- expected key and typed key
- timing between key events

This creates a stream of `AdaptiveSessionStep` values, which are then summarized into higher-level session payloads.

### 2. Session Payload

Each adaptive session can produce an `AdaptiveSessionPayload`, which includes:

- `lesson`
  The lesson state that was active during the session, including focused key and active alphabet.
- `keyStats`
  Hit and miss counts for each key, plus optional timing data.
- `transitions`
  Per-transition statistics, such as `fromKey`, `toKey`, count, and average time.
- `telemetry`
  Raw step telemetry plus derived missed digraphs and correction hotspots.

This payload is attached to persisted history when the session contributes to adaptive learning.

### 3. Digraph And Correction Analysis

The engine tracks more than single-key misses.

It also derives:

- `missedDigraphs`
  Places where a specific key pair or transition repeatedly breaks down.
- `correctionHotspots`
  Places where the user often recovers after an error.

That matters because many typing weaknesses are transition problems, not just isolated key problems.

### 4. Adaptive Profile Building

Saved sessions are transformed into `TrainingProfileSession` values and aggregated into a training profile snapshot.

That snapshot includes:

- session history
- key-level detail
- recent events
- streak state
- daily goal progress
- lesson feedback
- progress overview over time

This is what drives both the adaptive engine and the analysis dashboard.

### 5. Lesson Selection

The learning engine uses the profile state plus settings like:

- target WPM
- alphabet expansion
- unlock strategy
- weak-key recovery preference
- lesson length
- natural-word preference
- keyboard layout

to decide:

- which keys stay active
- which key should be focused next
- whether the alphabet should expand
- whether weak keys need recovery before unlocking more
- how much repetition and natural text to include

### 6. Mode Separation

Typa intentionally separates adaptive learning from fixed tests.

- `Learning`
  Optimizes for improvement. It selects and shapes lessons based on prior performance.
- `Test`
  Optimizes for measurement and controlled repetition. It supports time, words, or continuous runs with configurable sources.

## Practice Modes

### Learning Mode

Learning mode is designed to gradually build skill while keeping the active alphabet manageable.

Key controls include:

- unlock order
- target speed
- lesson length
- repeat count
- alphabet expansion speed
- recovery behavior for weak keys
- real-word preference

### Test Mode

Test mode supports:

- `Time`
- `Words`
- `Continuous`

and content sources:

- `Common Words`
- `Code Words`
- `Numbers`
- `Custom Words`

This makes it possible to use Typa as both a trainer and a benchmark tool.

## Keyboard Layout Support

Typa supports multiple layouts:

- QWERTY
- QWERTY (UK)
- Colemak
- Dvorak

The adaptive engine respects the selected layout when determining supported keys, active alphabets, and lesson generation.

## Appearance And UX

Typa is designed to feel more like a focused desktop tool than a browser speed test.

Appearance options include:

- font size
- line height
- letter spacing
- upcoming text opacity
- caret style
- caret color
- blink rate
- smooth caret animation
- noise texture background
- live stats visibility

The app also includes:

- a floating live stats dock
- a fullscreen-capable responsive main window
- transparent macOS titlebar integration
- animated results and profile surfaces

## Audio

Audio options currently include:

- sound packs: `Off`, `Clicky`, `Cream`, `Alpaca`
- configurable volume
- optional error sound feedback

These assets live in `Resources/` and are loaded locally.

## Data And Persistence

Typa is local-first.

- Settings are saved locally.
- Typing history is saved locally using SwiftData.
- The app attempts to use Application Support for persistent storage.
- If persistent storage is unavailable, it falls back to temporary or in-memory storage for the current launch.

The app also contains import and transfer models for moving history data into the current format.

## Profile And Analysis

The profile side of Typa is built around more than a simple best-WPM chart.

It tracks:

- per-session performance
- key detail and confidence
- transition timing
- recent events
- streaks
- daily goal completion
- last-lesson feedback
- adaptive progress over time

Examples of generated events include:

- unlocked keys
- new best speed
- daily goal completion
- streak updates

## Testing

The project includes unit tests under `TyperTests/`, currently covering:

- practice content fallback and diversification behavior
- settings mode mapping
- result mode identifiers
- font-size normalization

## Running The Project

Requirements:

- Xcode with macOS SwiftUI support
- a macOS target environment

Open the project in Xcode and run the main app target.

## Design Goals

Typa aims to balance:

- adaptive depth
- desktop-native polish
- low-friction practice
- readable analytics
- local ownership of data
  
## Credits & Inspiration
Typa stands on the shoulders of giants. This project is built with deep appreciation for:
- **Keybr**: For the foundational philosophy of adaptive, algorithmic typing practice.
- **Protypist**: For proving that a typing tool can be a premium, beautiful macOS citizen.
  
The project is intentionally not a clone of browser typing-test sites. The goal is a native trainer that can help you improve over repeated sessions while still feeling fast, quiet, and configurable.

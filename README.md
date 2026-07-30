<div align="center">

# Carbonara

**The AI-native post tool.**

Edit, generate, and finish — on your own models.

<sub><i>macOS 26 (Tahoe) · Apple Silicon</i></sub>

</div>

---

Carbonara is a native macOS non-linear editor built for a new kind of post workflow: you and your agents cut, generate, grade, and deliver inside one timeline. No accounts. No credits. No telemetry. Your footage and your API keys never answer to anyone else's cloud.

## The editor

A from-scratch Swift editor with the instincts of a finishing tool:

- **Timeline** — multi-track, frame-accurate, linked clips, multicam, nested sequences, beat detection.
- **Color** — a Metal grading pipeline: wheels, curves, hue curves, levels, LUTs (tetrahedral), highlights/shadows, glow, grain, vignette, chroma key.
- **Sound** — waveforms, metering, music beds, voice enhancement, on-device transcription and captions with word-accurate timing.
- **Delivery** — hardware-accelerated export, FCPXML interchange, project packages that travel.

## Generation, on your terms

Every generation flows through a pluggable provider layer. Bring the backends you already use:

- **[fal.ai](https://fal.ai)** — hosted frontier models (FLUX, LTX-Video, Stable Audio, MiniMax) with your own key. Paste it in Settings → Providers; verified in one click.
- **Higgsfield** — connect Carbonara as an MCP client to Higgsfield's hosted generation tools.
- **ComfyUI** *(in development)* — run local workflow graphs, including LTX-Video director-style shot workflows, straight into your media pool.

Results land in the project package atomically, resume across relaunches, and undo like any other edit.

## Built for agents

Carbonara exposes its entire editing surface over MCP. Point Claude Code, Codex, or Cursor at the running app:

```bash
claude mcp add --transport http carbonara http://127.0.0.1:19789/mcp
```

Your agent gets the same tools the in-app agent uses — inspect the timeline, place and trim clips, caption, grade, generate, export — with shared validation and a shared undo history. An edit from your agent is indistinguishable from your own.

The in-app agent panel is optional and runs on your own Anthropic API key.

## Private by architecture

- No sign-in, no subscription, no credit meter.
- No analytics, no crash reporting — diagnostics stay in the local system log.
- Transcription runs on-device with Apple's speech engine.
- Provider keys live in the macOS Keychain and requests go directly to the provider you chose.

## Building

Requires full Xcode 26+ (with the Metal Toolchain component) on Apple Silicon.

```bash
swift build
swift run
swift test
```

First-time setup on a new machine:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadComponent MetalToolchain
```

## Lineage

Carbonara is a fork of [Palmier Pro](https://github.com/palmier-io/palmier-pro) by Palmier, Inc. — a remarkable Swift-native editor foundation — rebuilt around local-first, bring-your-own-model generation. Distributed under the same license.

## License

Copyright (C) 2026 Palmier, Inc. (original work). Carbonara modifications are open source under [GPLv3](LICENSE).

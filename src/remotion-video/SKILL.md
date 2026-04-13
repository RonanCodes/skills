---
name: remotion-video
description: Generate programmatic videos using Remotion (React to video). Two modes — marketing promo and app demo walkthrough. Use when user wants to create a video, promo, demo, trailer, or walkthrough.
argument-hint: [--marketing | --demo] <project-or-topic>
allowed-tools: Bash(*) Read Write Edit Glob Grep
---

# Remotion Video

Generate MP4 videos from React components using Remotion.

## Usage

```
/remotion-video --marketing llm-wiki     # 30-60s promo video
/remotion-video --demo llm-wiki          # 1-3min walkthrough
/remotion-video my-project               # Defaults to --marketing
```

## Prerequisites

- Node.js 16+, FFmpeg (bundled with Remotion)
- If no Remotion project exists at `sites/videos/` or `videos/`, scaffold one:
  ```bash
  npx create-video@latest --template blank --tailwind
  ```

## --marketing Mode

1. **Research** — read README, key files, understand what the project does
2. **Script** (5-10 scenes, 30-60s total):
   - Hook/intro (2-3s)
   - Problem statement (3-5s)
   - Solution demo (10-15s)
   - Key features (5-10s, 2-3 highlights)
   - Call to action (3-5s)
3. **Build** — create React components per scene using `<Sequence>`, `<AbsoluteFill>`
4. **Animate** — use `interpolate(frame, [start, end], [from, to])` and `spring({ frame, fps })` for motion
5. **Style** — TailwindCSS for layout and typography
6. **Render** — `npx remotion render src/index.ts MainVideo out/video.mp4 --codec h264`

## --demo Mode

1. **Map features** — identify the app's 3-5 key features/flows
2. **Script** walkthrough (1-3min total):
   - Feature intro with animated UI mockup
   - Interaction highlight with text overlay
   - Result/output showcase
3. **Build** — same component approach, add text overlays explaining each step
4. **Render** — same render command

## Key Remotion Patterns

```tsx
// Video definition
<Composition id="MainVideo" component={Main} durationInFrames={900} fps={30} width={1920} height={1080} />

// Scene sequencing
<Sequence from={0} durationInFrames={90}><IntroScene /></Sequence>
<Sequence from={90} durationInFrames={150}><ProblemScene /></Sequence>

// Animation
const frame = useCurrentFrame();
const opacity = interpolate(frame, [0, 30], [0, 1], { extrapolateRight: "clamp" });
const scale = spring({ frame, fps: 30, config: { damping: 12 } });
```

## Output Defaults

| Setting | Value |
|---------|-------|
| Resolution | 1920x1080 |
| FPS | 30 |
| Codec | H.264 |
| CRF | 18 (high quality) |
| Duration | 30-60s (marketing), 1-3min (demo) |

## Render Command

```bash
npx remotion render src/index.ts MainVideo out/video.mp4 --codec h264
```

## Licensing

Free for individuals and companies with 3 or fewer employees. Larger companies need a license from remotion.pro.

For detailed Remotion API reference, install the official skills: `remotion-dev/skills`.

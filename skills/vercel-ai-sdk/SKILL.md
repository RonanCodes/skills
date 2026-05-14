---
name: vercel-ai-sdk
description: Build, debug, and tune Vercel AI SDK (v6) code — Core primitives (streamText, generateText, generateObject, streamObject, embed, embedMany, tool() agentic loops, wrapLanguageModel middleware), UI hooks (useChat, useCompletion, useObject), and provider-specific features for Anthropic (prompt caching, extended thinking), OpenAI (reasoning effort, structured outputs), and Google (grounding, thinking budget). Covers the v6 UIMessage parts[] wire protocol, DefaultChatTransport, message persistence, abort/retry, edge-runtime gotchas (Cloudflare Workers process.env), and v5 → v6 migration. Use when the user mentions Vercel AI SDK, `ai` package, useChat, streamText, generateObject, structured output with Zod, agentic tools, prompt caching, AI SDK v6, AI SDK migration, or wires Anthropic/OpenAI/Google through the unified provider interface.
category: development
allowed-tools: Read Write Edit Bash WebFetch
---

# Vercel AI SDK

Wire the Vercel AI SDK v6 (`ai`, `@ai-sdk/react`, `@ai-sdk/anthropic`, `@ai-sdk/openai`, `@ai-sdk/google`) into a TypeScript app. Default streaming UI, structured output via Zod, agentic tool loops, multi-provider routing, and middleware.

Canonical decision: this is the user's default for any LLM-touching code in TanStack Start / Cloudflare Workers projects. Drop to a raw provider SDK only when the AI SDK has not wrapped a feature you need (see "When NOT to use" below).

## On auto-load: prompt the user first

The user never invokes this skill manually; the harness auto-loads it via fuzzy match on the description's keywords. By the time these instructions are in your context, the user has not actively chosen to add the AI SDK. So:

**Before introducing the SDK to a project that doesn't already use it** (i.e. before any `pnpm add ai @ai-sdk/...` or a new `lib/models.ts` scaffold), prompt the user via `AskUserQuestion`:

> Question: "I'm about to wire the Vercel AI SDK into this project for `<feature>`. Sound good, or would you rather take a different approach?"
> Options:
> 1. **Wire it. Vercel AI SDK is the right default** (recommended)
> 2. **Wait, explain the alternatives first**
> 3. **Use a raw provider SDK instead**
> 4. **Skip the AI feature for now**

**For projects that already use the SDK** (check `package.json` for `"ai"` + `"@ai-sdk/*"` deps), skip the prompt and proceed with feature work. Don't re-confirm every change inside a single conversation.

**For STRUCTURAL changes inside an existing-SDK project** (adding a new provider package, enabling prompt caching for the first time, introducing tool calling where none existed, switching the primary model), a single quick `AskUserQuestion` is still worth it.

For pure code-tweak changes (refactoring an existing `streamText` call, tightening a Zod schema, adding a log line), just proceed. No prompt.

Reason: the user prefers being looped in on structural changes since auto-loaded skills can otherwise surprise-install dependencies. See the `feedback_skills_prompt_before_structural_change` memory for the durable rule.

## When to use

Reach for this skill when the user wants any of:

- A streaming chatbot UI in React (`useChat`)
- Structured output with Zod validation (`generateObject`)
- Live-filling structured output in the UI (`streamObject` + `useObject`)
- An agentic loop: model → tool → model → tool (`tool()` + `stopWhen`)
- Multi-provider routing or A/B between Anthropic / OpenAI / Google
- Embeddings for RAG or semantic search (`embed`, `embedMany`)
- Per-call middleware: caching, redaction, logging, RAG injection (`wrapLanguageModel`)
- Anthropic prompt caching, OpenAI reasoning effort, Google grounding — anything that lives on `providerOptions`
- v5 → v6 migration (UIMessage parts, transport object, `inputSchema` vs `parameters`)

## When NOT to use

Drop to the raw provider SDK (`@anthropic-ai/sdk`, `openai`, `@google/generative-ai`) when:

- You need a feature the AI SDK has not wrapped yet (e.g. brand-new Anthropic message batches, files API, fine-tuning endpoints)
- You need a provider-specific SSE event type that has no AI SDK part-type equivalent
- The abstraction tax (one extra dep + one extra layer of types) is not worth it for a single throwaway call
- You are inside provider-specific code that has zero portability requirement and benefits from direct SDK ergonomics

For everything else (chat UIs, agentic loops, structured output, provider portability), the AI SDK is the default.

## Decision tree

```
Need to talk to an LLM?
├─ User-facing text reply? ───────────────► streamText + result.toUIMessageStreamResponse()
├─ Backfill / non-interactive text? ──────► generateText
├─ Structured JSON output? ───────────────► generateObject (+ Zod)
│   └─ Want to render it as it builds? ───► streamObject + useObject
├─ Chatbot UI in React? ──────────────────► useChat + DefaultChatTransport (server runs streamText)
├─ Single-turn text completion UI? ───────► useCompletion (server runs streamText)
├─ Vector embeddings? ────────────────────► embed / embedMany
├─ Multimodal (image, audio, TTS)? ───────► generateImage / transcribe / speech
└─ Multi-step with tools? ────────────────► generateText/streamText + tools + stopWhen(stepCountIs(N))
```

## Core recipes

### 1. Streaming chat (Anthropic on Cloudflare Workers)

Server route (TanStack Start file-route example):

```ts
import { streamText, convertToModelMessages, type UIMessage } from 'ai';
import { createAnthropic } from '@ai-sdk/anthropic';

export const Route = createFileRoute('/api/chat')({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { env } = requireWorkerContext();
        const anthropic = createAnthropic({ apiKey: env.ANTHROPIC_API_KEY });
        const body = (await request.json()) as { messages: UIMessage[] };

        const result = streamText({
          model: anthropic('claude-sonnet-4-5'),
          system: 'You are a helpful assistant.',
          messages: convertToModelMessages(body.messages),
          temperature: 0.7,
          abortSignal: request.signal,
          onError: ({ error }) => console.error('stream error', error),
        });

        return result.toUIMessageStreamResponse();
      },
    },
  },
});
```

Client:

```tsx
import { useChat } from '@ai-sdk/react';
import { DefaultChatTransport } from 'ai';
import { useState } from 'react';

function Chat() {
  const [draft, setDraft] = useState('');
  const { messages, sendMessage, status, stop, error } = useChat({
    transport: new DefaultChatTransport({ api: '/api/chat' }),
  });

  return (
    <form onSubmit={(e) => {
      e.preventDefault();
      if (!draft.trim() || status !== 'ready') return;
      sendMessage({ text: draft });
      setDraft('');
    }}>
      {messages.map((m) => (
        <div key={m.id}>
          {m.parts.filter((p) => p.type === 'text').map((p, i) => (
            <span key={i}>{(p as { text: string }).text}</span>
          ))}
        </div>
      ))}
      <input value={draft} onChange={(e) => setDraft(e.target.value)} />
      {status === 'streaming' && <button type="button" onClick={stop}>Stop</button>}
    </form>
  );
}
```

### 2. Structured output with Zod

```ts
import { generateObject } from 'ai';
import { z } from 'zod';

const Rubric = z.object({
  grammar: z.number().int().min(1).max(5),
  feedbackEn: z.string(),
  errors: z.array(z.object({
    incorrect: z.string(),
    correction: z.string(),
  })).default([]),
});

const { object: rubric } = await generateObject({
  model: anthropic('claude-sonnet-4-5'),
  schema: Rubric,
  schemaName: 'RoleplayRubric',
  system: 'You are a Dutch language grader.',
  prompt: transcript,
});
```

For live-filling UI, swap to `streamObject` on the server and `useObject` on the client (same schema both sides).

### 3. Anthropic prompt caching (high-leverage cost cut)

Mark long, repeated content (system prompt, RAG context, doc retrieval) with a cache breakpoint. First call writes cache, subsequent calls within ~5 minutes read at ~10% cost.

```ts
const result = streamText({
  model: anthropic('claude-sonnet-4-5'),
  messages: [
    {
      role: 'system',
      content: [
        {
          type: 'text',
          text: bigSystemPrompt, // >= ~1024 tokens to be worth it
          providerOptions: {
            anthropic: { cacheControl: { type: 'ephemeral' } },
          },
        },
      ],
    },
    ...convertToModelMessages(body.messages),
  ],
});

// After streaming:
const meta = await result.providerMetadata;
console.log(meta?.anthropic?.cacheReadInputTokens, meta?.anthropic?.cacheCreationInputTokens);
```

Up to 4 cache breakpoints per request. Place them on the most-repeated content first (system, then static RAG, then few-shot examples).

### 4. Tool calling with Zod

```ts
import { tool, stepCountIs } from 'ai';
import { z } from 'zod';

const lookupCustomer = tool({
  description: 'Look up a customer by id; returns name, plan, region.',
  inputSchema: z.object({ id: z.string() }),
  execute: async ({ id }, { abortSignal }) => {
    const row = await db.select().from(customers).where(eq(customers.id, id));
    return row[0] ?? { error: 'not_found' };
  },
});

const result = await generateText({
  model: anthropic('claude-sonnet-4-5'),
  tools: { lookupCustomer },
  stopWhen: stepCountIs(5),
  prompt: 'Summarise customer cust_42.',
  onStepFinish: ({ stepNumber, toolCalls }) => log.debug({ stepNumber, toolCalls }),
});

// result.steps[] has every intermediate call + result
```

Note: v6 uses `inputSchema`, not v5's `parameters`. Tool execute receives `{ toolCallId, messages, abortSignal, experimental_context }` as second arg.

### 5. `streamObject` + `useObject` for a live rubric

Server:

```ts
import { streamObject } from 'ai';

const result = streamObject({
  model: anthropic('claude-sonnet-4-5'),
  schema: Rubric,
  prompt: transcript,
});

return result.toTextStreamResponse();
```

Client:

```tsx
import { useObject } from '@ai-sdk/react';

const { object, submit, isLoading } = useObject({
  api: '/api/grade.stream',
  schema: Rubric,
});

// object is DeepPartial<z.infer<typeof Rubric>>; renders progressively
```

### 6. `useChat` with persistence (server-side history)

Client transport ships only the new message; server reloads history.

```tsx
const { messages, sendMessage, status } = useChat({
  id: chatId, // stable per conversation
  messages: initialMessages, // server-loaded on mount
  transport: new DefaultChatTransport({
    api: '/api/chat',
    prepareSendMessagesRequest: ({ messages, id }) => ({
      body: { message: messages[messages.length - 1], id },
    }),
  }),
});
```

Server (TanStack Start):

```ts
const { id, message } = await request.json();
const history = await loadMessages(id);
const all = [...history, message];

const result = streamText({
  model: anthropic('claude-sonnet-4-5'),
  messages: convertToModelMessages(all),
});

return result.toUIMessageStreamResponse({
  originalMessages: all,
  onFinish: async ({ messages }) => {
    await saveMessages(id, messages); // persist final assistant turn
  },
});
```

Pair with `createIdGenerator({ prefix: 'msg', size: 16 })` for stable ids across client + server.

### 7. Multimodal input (image)

```tsx
// Client: pass files alongside text
sendMessage({
  text: 'Describe this image in Dutch.',
  files: [imageFile], // File | Blob
});

// Server: convertToModelMessages handles file parts automatically
// Anthropic/OpenAI/Google all accept image input through the same shape
```

## Provider-specific tricks

### Anthropic

- **Prompt caching** (`providerOptions.anthropic.cacheControl: { type: 'ephemeral' }`) — see recipe 3.
- **Extended thinking** — `providerOptions.anthropic.thinking: { type: 'adaptive' }` and `effort: 'low' | 'medium' | 'high' | 'max'`. Returns `reasoningText` on the result.
- **Provider-specific tools** on `anthropic.tools`: `computer_20251124()`, `bash_20250124()`, `textEditor_20250728()`, `codeExecution_20260120()`, `webSearch_20250305()`, `webFetch_20250910()`.
- **PDF input** as a `file` part with `mediaType: 'application/pdf'`.

### OpenAI

- **Responses API is the default since v5** — `openai('gpt-5')` uses it. Force chat with `openai.chat('gpt-5')`.
- **Reasoning effort** — `providerOptions.openai.reasoningEffort: 'low' | 'medium' | 'high'` for `gpt-5`, `o3`, `o4-mini`.
- **Structured outputs** — strict JSON Schema mode is default. Disable with `providerOptions.openai.strictJsonSchema: false` when your schema uses unions/records OpenAI's strict mode rejects.
- **Prompt caching** — automatic above ~1024 tokens. Read counts from `providerMetadata?.openai?.cachedPromptTokens`. No config needed.
- **Image generation** — `openai.image('gpt-image-1')` or `openai.image('dall-e-3')`.

### Google

- **Grounding via search** — `tools: { search: google.tools.googleSearch({}) }`. Result exposes `sources` and `groundingMetadata`.
- **Thinking budget** — `providerOptions.google.thinkingBudget: 8192` (Gemini 2.5) or `thinkingLevel: 'medium'` (Gemini 3). Set `includeThoughts: true` for reasoning summaries.
- **Code execution** — `tools: { code: google.tools.codeExecution({}) }` runs Python sandbox.
- **PDF + YouTube URL inputs** — pass as `file` parts; the SDK fetches automatically except for `generativelanguage.googleapis.com` and YouTube URLs (those are handled provider-side).
- **Structured outputs** — on by default. Disable with `providerOptions.google.structuredOutputs: false` for schemas with unions/records.

## Production gotchas

- **Cloudflare Workers `process.env`** — the static `import { anthropic }` reads `process.env.ANTHROPIC_API_KEY`, which is undefined in Workers. Always use `createAnthropic({ apiKey: env.ANTHROPIC_API_KEY })` (same shape for `createOpenAI`, `createGoogleGenerativeAI`) with the runtime-bound `env`.
- **Abort propagation** — pass `request.signal` as `abortSignal` so user disconnect cancels the upstream call. `onAbort` fires; `onFinish` does **not**.
- **Retry budget** — `maxRetries` defaults to 2, exponential backoff. Bump down to 0 on user-facing low-latency paths so failures fail fast.
- **Error UI** — `useChat` exposes `error` and `regenerate()`. Show a retry button on `status === 'error'`. Server stream errors arrive as `error` parts on `fullStream` and do not crash the connection (by design).
- **Token accounting** — `result.usage` is per-turn. For multi-step agent loops, use `result.totalUsage` or sum across `result.steps[*].usage`. Logging just `usage` after a loop returns only the final step.
- **Edge runtime fetch** — pass `fetch:` to inject a wrapped fetch for proxying / logging / mocking. Useful when running behind a forward proxy or in tests.
- **Custom data parts** — emit `data-progress`, `data-citations`, etc. from the server for non-LLM channel data. Client reads `part.type.startsWith('data-')` on `UIMessage.parts[]`.

## Common pitfalls

- **`UIMessage` vs `ModelMessage`.** UI uses `parts[]`; the model uses content blocks. Always `convertToModelMessages(uiMessages)` at the server boundary before handing to `streamText`. Skipping this passes through for trivial cases and silently breaks once a tool call or attachment is in the history.
- **Reading `m.content`** — does not exist on v6 `UIMessage`. Always `m.parts.filter(p => p.type === 'text').map(p => p.text).join('')`.
- **`initialMessages` identity** — pass a memoised array (`useMemo`) or you reset the chat on every render.
- **v5 → v6 `useChat`** — `input`, `handleInputChange`, `handleSubmit` are gone. You own the input state, you call `sendMessage({ text })`. Replace any of those v5 props on migration.
- **Tool schema field** — v6 is `inputSchema`, not `parameters`. Update tool definitions on migration.
- **Double-counting tokens** — read `result.totalUsage` after agent loops, not the last step's `usage`.
- **Transport reconnect loops** — return proper 4xx status on permanent failures so the transport does not retry forever.
- **Schema drift on persisted messages** — when storing tool calls in DB, validate on load with `validateUIMessages({ messages, tools })` so old shapes do not crash the model.

## Migration notes (v5 → v6)

| v5 | v6 |
|---|---|
| `useChat({ api: '/api/chat' })` | `useChat({ transport: new DefaultChatTransport({ api: '/api/chat' }) })` |
| `input`, `handleInputChange`, `handleSubmit` | Own input state; `sendMessage({ text })` |
| `m.content: string` | `m.parts[]: Part[]` |
| `tool({ parameters: z.object() })` | `tool({ inputSchema: z.object() })` |
| `maxSteps` on `useChat` | `stopWhen` / `sendAutomaticallyWhen` |
| `experimental_attachments` | First-class `file` parts |
| `result.text` for full streamed text | Same on `generateText`; on `streamText` use `await result.text` (promise) |
| Hooked fetch from inside the hook | Explicit transport object (`DefaultChatTransport`, `DirectChatTransport`, custom) |

## See also

- Wiki concept pages in `llm-wiki-ai-research`:
  - [vercel-ai-sdk-overview](https://github.com/RonanCodes/llm-wiki/) — what the SDK is, when to use it
  - [vercel-ai-sdk-core-primitives](https://github.com/RonanCodes/llm-wiki/) — full signature reference
  - [vercel-ai-sdk-ui-hooks](https://github.com/RonanCodes/llm-wiki/) — useChat, transport, parts wire protocol
  - [vercel-ai-sdk-lekkertaal-gap-audit](https://github.com/RonanCodes/llm-wiki/) — example gap audit on a real codebase
- Official docs: <https://ai-sdk.dev/docs/ai-sdk-core>, <https://ai-sdk.dev/docs/ai-sdk-ui>
- Related skills: `/ro:new-tanstack-app` (the stack this sits on), `/ro:cf-ship` (deployment), `claude-api` (when dropping to raw Anthropic SDK)

# FoundationModelsKit

Utilities for shipping apps and tools with Apple's Foundation Models framework.

FoundationModelsKit helps apps, CLIs, benchmarks, and developer tools use Foundation Models with runtime checks, Codable request and result types, schema conversion, token accounting, context recovery, and concrete tools.

It is designed to complement Apple's Foundation Models framework and Apple's Foundation Models Utilities. Use Apple's utilities for OpenAI-compatible `LanguageModel` adapters and extensions to FoundationModels itself. Use FoundationModelsKit when you need app, CLI, or benchmark support around on-device and Private Cloud Compute execution.

## Products

The package exposes four products:

- `FoundationModelsKit`: runtime inspection, capability use cases, model configuration, schemas, token accounting, transcript utilities, error projection, and conversation state.
- `FoundationModelsTools`: `Tool` implementations for Apple platform capabilities and web services. This product re-exports `FoundationModelsKit`.
- `FoundationModelsToolsTestSupport`: in-memory Calendar and Reminders services, scripted confirmation, and deterministic fixtures for downstream tests.
- `FoundationModelEvaluation`: runtime fingerprints, repeatable evaluation traces, and Feedback Assistant attachments. It depends on `FoundationModelsKit`.

## What Is Included

### Runtime Readiness

Inspect whether Foundation Models can actually run in the current process.

- On-device availability
- Private Cloud Compute availability
- PCC entitlement status
- PCC quota state
- Supported language metadata
- Codable status models for logs, CLIs, and benchmarks

```swift
import FoundationModelsKit

let inspector = FoundationModelsRuntimeInspector()
let onDevice = inspector.status(for: .onDevice)
let pcc = inspector.status(for: .privateCloudCompute)

if pcc.isRunnableInCurrentProcess {
    print("PCC is available and authorized.")
} else {
    print("PCC unavailable: \(pcc.reason?.rawValue ?? "unknown")")
}
```

### Generation Use Cases

Wrap Foundation Models calls in request and result types that are easy to test, serialize, and record.

```swift
import FoundationModelsKit

let request = FoundationModelTextGenerationRequest(
    prompt: "Explain actor isolation in one paragraph.",
    systemPrompt: "Answer for a Swift developer.",
    generationOptions: FoundationModelGenerationOptions(
        temperature: 0.3,
        maximumResponseTokens: 300
    ),
    context: FoundationModelInvocationContext(source: .cli)
)

let result = try await FoundationModelTextGenerationUseCase().execute(request)
print(result.content)
```

Available use cases include:

- `FoundationModelTextGenerationUseCase`
- `FoundationModelStreamingTextGenerationUseCase`
- `FoundationModelStructuredGenerationUseCase`
- `FoundationModelDynamicSchemaGenerationUseCase`
- `FoundationModelAvailabilityUseCase`
- `FoundationModelRuntimeInspectionUseCase`
- `FoundationModelQuotaUsageInspectionUseCase`
- `FoundationModelSupportedLanguagesUseCase`

### Coordinated Runtime Fallback

`FoundationModelExecutionCoordinator` serializes calls across app-supplied sessions and opens a durable circuit after rate limits, quota exhaustion, network failures, or unavailable PCC service. A request error controls routing; availability and quota checks remain advisory.

Each fallback route must come from the app. Before crossing runtimes, its `prepareForFallback` closure receives a `FoundationModelRouteTransition`, which is where the app should compact or rebuild a PCC transcript for the smaller on-device context. The coordinator won't retry guardrail violations, refusals, decoding failures, or a request marked `mayHaveSideEffects`.

Successful and failed executions carry a `FoundationModelRoutingTrace` containing attempted runtimes, the selected runtime, projected failures, cooldowns, circuit state, and the retry decision. `FoundationModelDefaultsCircuitStore` persists circuit state; tests can inject `FoundationModelInMemoryCircuitStateStore`.

### Model Configuration and Adapters

FoundationModelsKit supports Apple's on-device Foundation Models runtime and Private Cloud Compute runtime where available. It also supports Apple Foundation Models adapter files through `SystemLanguageModel.Adapter`.

```swift
import FoundationModelsKit

let adapterURL = URL(fileURLWithPath: "/path/to/model.fmadapter")
let request = FoundationModelTextGenerationRequest(
    prompt: "Summarize this document.",
    adapterURL: adapterURL,
    context: FoundationModelInvocationContext(source: .app)
)

let result = try await FoundationModelTextGenerationUseCase().execute(request)
```

OpenAI-compatible hosted models are intentionally not duplicated here. Use Apple's Foundation Models Utilities for that adapter, then use FoundationModelsKit for runtime status, schema conversion, token accounting, and run metadata.

### Schema Utilities

Decode and validate a supported JSON Schema subset, then convert it into a Foundation Models `GenerationSchema`.

```swift
import FoundationModelsKit

let schema = try JSONDecoder().decode(
    FoundationModelsJSONSchema.self,
    from: Data("""
    {
      "title": "BookRecommendation",
      "type": "object",
      "properties": {
        "title": { "type": "string" },
        "reason": { "type": "string" }
      },
      "required": ["title", "reason"],
      "additionalProperties": false
    }
    """.utf8)
)

try schema.validate()
let generationSchema = try schema.generationSchema(rootName: "BookRecommendation")
```

The schema utilities are built for CLIs, benchmarks, and user-authored schema files. They report exact JSON pointer-style paths for unsupported keywords and invalid declarations.

### Token Accounting and Context Budgets

Use transcript token utilities to estimate context size, inspect model token usage, and trim transcript entries before context overflow becomes a user-visible failure.

```swift
import FoundationModels
import FoundationModelsKit

let transcript = Transcript(entries: [
    .prompt(Transcript.Prompt(segments: [
        .text(Transcript.TextSegment(content: "Explain Foundation Models."))
    ]))
])

let estimate = transcript.safeEstimatedTokenCount
let trimmed = transcript.entriesWithinTokenBudget(4_096)
```

FoundationModelsKit also normalizes model-reported usage through `ModelTokenUsage`, including cached input tokens and reasoning output tokens where the framework exposes them.

### Conversation Engine

`FoundationModelConversationEngine` is a small runtime for app and CLI chat surfaces. It handles:

- Prompt validation
- Streaming and one-shot responses
- Cancellation
- Runtime switching
- Reasoning options for PCC
- Adapter-safe defaults
- Sliding-window context trimming
- Summary-based context-overflow recovery
- Token usage snapshots

```swift
import FoundationModelsKit

let engine = FoundationModelConversationEngine(
    configuration: FoundationModelConversationConfiguration(
        baseInstructions: "You are a concise Swift assistant.",
        summaryInstructions: "Summarize the conversation for continuation.",
        summaryPromptPreamble: "Create a compact continuation summary.",
        conversationUserLabel: "User:",
        conversationAssistantLabel: "Assistant:",
        continuationNote: "Continue naturally from the summary.",
        enableSlidingWindow: true
    )
)

let answer = try await engine.sendMessage("What does Sendable protect?")
print(answer)
```

### Error Projection

Foundation Models errors change across SDK generations. `FoundationModelErrorProjection` maps framework errors into stable categories for logs, CLIs, UI, and benchmark reports.

```swift
do {
    _ = try await FoundationModelTextGenerationUseCase().execute(request)
} catch {
    if let projection = FoundationModelErrorProjection.project(error) {
        print(projection.category.rawValue)
    }
}
```

### Generated Tool Execution Policy

`FoundationModelToolExecutionPolicy` owns one turn's tool budget. It validates generated JSON before app code runs, detects repeated `(tool, arguments)` calls, and caps calls, repairs, elapsed time, and actual output tokens.

The validator supports required properties, string or numeric enums, integer and number ranges, arrays, `anyOf`, and discriminated unions. Policy decisions return typed `loopDetected`, `invalidArguments`, or `budgetExceeded` results. A side-effecting call must choose app-owned confirmation or a nonempty idempotency key.

```swift
let policy = FoundationModelToolExecutionPolicy(
    budget: FoundationModelToolExecutionBudget(
        maxCalls: 6,
        maxRepairs: 2,
        maxDuration: .seconds(10),
        maxOutputTokens: 256
    )
)

let arguments = try FoundationModelToolValue(generatedContent: generatedArguments)
let result = try await policy.execute(
    tool: "lookup",
    arguments: arguments,
    schema: toolSchema,
    outputTokenEstimator: estimateOutputTokens
) {
    try await lookup(arguments)
}
```

### Evaluation Evidence

Add `FoundationModelEvaluation` when an app or benchmark needs evidence that survives OS and device changes. `FoundationModelRuntimeFingerprint.capture()` records OS version and build, device identifier, locale, runtime, context size, and the public model variant when the SDK exposes it.

`FoundationModelEvaluationRunner` records ordered tool events, repair count, latency, token usage, schema validity, refusal or error category, and final success without collecting prompt or response text. `FoundationModelFeedbackBundleBuilder` can pair that trace with `LanguageModelSession.logFeedbackAttachment`; Apple's attachment may contain session content, so consent and redaction stay with the app.

For deterministic tests, wrap any `FoundationModelTextGenerating` implementation in `FoundationModelRecordingTextGenerator`, export its `FoundationModelTextGenerationCassette`, then load that cassette with `FoundationModelReplayTextGenerator`. Replays match every semantic request field except the correlation ID and consume repeated recordings in their original request order.

```swift
let recorder = FoundationModelRecordingTextGenerator(base: liveGenerator)
_ = try await recorder.generateText(for: request)
let cassette = await recorder.cassette()

let replay = try FoundationModelReplayTextGenerator(cassette: cassette)
let deterministicResult = try await replay.generateText(for: request)
```

Cassettes contain complete prompts, instructions, adapter URLs, and responses. Creating or exporting one is an explicit app decision; the package doesn't redact or persist it automatically. `FoundationModelEvaluationSnapshot` removes run IDs, dates, and latency so checked-in golden comparisons report drift only in stable evaluation fields.

### Tools

`FoundationModelsTools` provides tools for real app capabilities. Calendar and Reminders reads are separate from mutations. Mutation tools cannot be initialized without an app-owned confirmation provider, and model-authored arguments never contain an approval flag.

```swift
import FoundationModels
import FoundationModelsTools

let confirmation = ToolMutationConfirmationHandler { request in
    // Present request.summary and request.details in app-owned UI.
    let approved = await confirmationUI.confirm(request)
    return approved
        ? .approved()
        : .denied(reason: "The user cancelled the change.")
}

// Share one long-lived EventKit store between each domain's read and mutation tools.
let calendar = EventKitCalendarService()
let reminders = EventKitRemindersService()

let session = LanguageModelSession(
    tools: [
        WeatherTool(),
        CalendarReadTool(service: calendar),
        RemindersReadTool(service: reminders),
        CalendarMutationTool(service: calendar, confirmation: confirmation),
        RemindersMutationTool(service: reminders, confirmation: confirmation)
    ]
)

let response = try await session.respond(
    to: "Check the weather and help me plan tomorrow morning."
)
```

Available tools:

- `WeatherTool`: current weather through OpenMeteo
- `WebTool`: Exa-backed web search
- `WebMetadataTool`: page title, description, and image metadata
- `ContactsTool`: search, read, and create contacts
- `CalendarReadTool`: query and read events
- `CalendarMutationTool`: create and update events after app-owned confirmation
- `RemindersReadTool`: query reminders
- `RemindersMutationTool`: create, update, complete, and delete reminders after app-owned confirmation
- `LocationTool`: current location, geocoding, reverse geocoding, place search, and distance
- `HealthTool`: authorized HealthKit reads
- `MusicTool`: Apple Music search and playback controls

The tools preserve platform permission boundaries. They do not fabricate unavailable Health, Contacts, Calendar, Location, Music, or Reminders data.

### Mutation Safety

Calendar and Reminders use four public boundaries:

1. Read services (`CalendarReading` and `RemindersReading`) expose no write methods.
2. Mutation services (`CalendarMutating` and `RemindersMutating`) are injected into mutation-only tools.
3. `ToolMutationConfirming` belongs to the host app and reviews the exact `ToolMutationRequest` immediately before execution.
4. Every executed mutation returns a typed `ToolMutationReceipt`, including the committed resource identifier. Failures throw `ToolMutationExecutionError` with the same receipt.

Receipts distinguish `.notAttempted`, `.notCommitted`, `.committed`, and `.unknown`. An EventKit error after a save begins is intentionally `.unknown`; callers must not claim that a retry is safe when the system cannot prove whether the first write committed.

The old `CalendarTool` and `RemindersTool` remain source-compatible for migration, but are deprecated. Their zero-argument initializers are read-capable and fail closed with a `.confirmationRequired` receipt for every mutation. Pass a confirmation provider explicitly, or migrate to the split tools.

For tests, add the `FoundationModelsToolsTestSupport` product and inject `InMemoryCalendarService`, `InMemoryRemindersService`, and `ScriptedToolMutationConfirmer`. No Calendar or Reminders permission is needed for these fixtures.

## Requirements

- macOS 26.0+
- iOS 26.0+
- Swift 6.2+
- Xcode 26.0+

Private Cloud Compute APIs and some reasoning controls require newer SDK/runtime availability and are guarded in code.

## Installation

Add the package dependency:

```swift
dependencies: [
    .package(
        url: "https://github.com/rryam/FoundationModelsKit.git",
        from: "3.0.0"
    )
]
```

Use only the products needed by each target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(
            name: "FoundationModelsKit",
            package: "FoundationModelsKit"
        ),
        .product(
            name: "FoundationModelsTools",
            package: "FoundationModelsKit"
        ),
        .product(
            name: "FoundationModelEvaluation",
            package: "FoundationModelsKit"
        )
    ]
)
```

Add `FoundationModelsToolsTestSupport` only to targets that need fixtures:

```swift
.testTarget(
    name: "YourTargetTests",
    dependencies: [
        .product(
            name: "FoundationModelsToolsTestSupport",
            package: "FoundationModelsKit"
        )
    ]
)
```

## Privacy and Keys

Some tools require platform permissions and usage descriptions:

- Calendar: `NSCalendarsUsageDescription`
- Contacts: `NSContactsUsageDescription`
- Health: `NSHealthShareUsageDescription`
- Location: `NSLocationWhenInUseUsageDescription`
- Music: `NSAppleMusicUsageDescription`
- Reminders: `NSRemindersUsageDescription`

`WebTool` uses Exa and requires an API key. Do not ship API keys inside a client app bundle. Prefer a server endpoint that stores the key in an environment variable and forwards only the safe request shape from your app.

## Relationship to Apple's Utilities

FoundationModelsKit is intentionally complementary to Apple's Foundation Models Utilities.

Use Apple's utilities for:

- OpenAI-compatible `LanguageModel` adapters
- Protocol-native `DynamicProfile` helpers
- Generic model-facing skills if Apple keeps them in that package

Use FoundationModelsKit for:

- Runtime and PCC readiness checks
- Codable request and result types
- Codable execution metadata
- Error projection
- JSON Schema validation and conversion
- Token accounting
- Conversation recovery
- Request serialization, durable circuits, and explicit runtime fallback
- Runtime tool-argument validation and per-turn execution budgets
- Model evaluation traces and Feedback Assistant bundles
- Concrete Apple platform tools
- App, CLI, and benchmark workflows

## Validation

Run the package checks locally:

```bash
swift build
swift test
```

## License

See [LICENSE](LICENSE).

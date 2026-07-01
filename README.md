# FoundationModelsKit

Utilities for shipping apps and tools with Apple's Foundation Models framework.

FoundationModelsKit helps apps, CLIs, benchmarks, and developer tools use Foundation Models with runtime checks, Codable request and result types, schema conversion, token accounting, context recovery, and concrete tools.

It is designed to complement Apple's Foundation Models framework and Apple's Foundation Models Utilities. Use Apple's utilities for OpenAI-compatible `LanguageModel` adapters and extensions to FoundationModels itself. Use FoundationModelsKit when you need app, CLI, or benchmark support around on-device and Private Cloud Compute execution.

## Products

The package exposes two products:

- `FoundationModelsKit`: runtime inspection, capability use cases, model configuration, schemas, token accounting, transcript utilities, error projection, and conversation state.
- `FoundationModelsTools`: `Tool` implementations for Apple platform capabilities and web services. This product re-exports `FoundationModelsKit`.

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

### Tools

`FoundationModelsTools` provides tools for real app capabilities.

```swift
import FoundationModels
import FoundationModelsTools

let session = LanguageModelSession(
    tools: [
        WeatherTool(),
        CalendarTool(),
        RemindersTool()
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
- `CalendarTool`: create, query, read, and update events
- `RemindersTool`: create, query, update, complete, and delete reminders
- `LocationTool`: current location, geocoding, reverse geocoding, place search, and distance
- `HealthTool`: authorized HealthKit reads
- `MusicTool`: Apple Music search and playback controls

The tools preserve platform permission boundaries. They do not fabricate unavailable Health, Contacts, Calendar, Location, Music, or Reminders data.

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
        branch: "main"
    )
]
```

Use the core product, the tools product, or both:

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

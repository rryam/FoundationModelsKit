# ``FoundationModelsKit``

Reusable runtime, schema, token, and conversation utilities for Apple's Foundation Models framework.

## Overview

`FoundationModelsKit` provides app- and CLI-ready building blocks around the Foundation Models framework. Use it when you need stable request and result types, runtime inspection, token accounting, schema conversion, or a managed conversation engine on top of `LanguageModelSession`.

The package is designed to keep Foundation Models code reusable outside a single app target:

- **Runtime inspection.** Check on-device and Private Cloud Compute availability, process authorization, and quota state with ``FoundationModelsRuntimeInspector``.
- **Generation use cases.** Wrap text, streaming text, structured output, and dynamic schema generation in request/result types that are easy to test and log.
- **Schema utilities.** Decode, validate, and convert a supported JSON Schema subset into Foundation Models `GenerationSchema` values with ``FoundationModelsJSONSchema``.
- **Token accounting.** Estimate transcript size, inspect model token usage, and trim transcript entries to a target budget.
- **Conversation engine.** Use ``FoundationModelConversationEngine`` for prompt validation, streaming, cancellation, context-window recovery, and summary-based continuation.
- **Error projection.** Convert Foundation Models framework errors into stable, machine-readable categories with ``FoundationModelErrorProjection``.

## Topics

### Runtime Inspection

- ``FoundationModelRuntime``
- ``FoundationModelsRuntimeInspector``
- ``FoundationModelRuntimeStatus``
- ``FoundationModelQuotaUsage``
- ``FoundationModelAvailability``
- ``FoundationModelSupportedLanguages``

### Generation

- ``FoundationModelTextGenerationUseCase``
- ``FoundationModelStreamingTextGenerationUseCase``
- ``FoundationModelStructuredGenerationUseCase``
- ``FoundationModelDynamicSchemaGenerationUseCase``
- ``FoundationModelTextGenerationRequest``
- ``FoundationModelStreamingTextGenerationRequest``
- ``FoundationModelStructuredGenerationRequest``
- ``FoundationModelDynamicSchemaGenerationRequest``

### Conversation Runtime

- ``FoundationModelConversationEngine``
- ``FoundationModelConversationConfiguration``
- ``FoundationModelConversationSummary``
- ``FoundationModelGenerationOptions``
- ``FoundationModelGuardrails``
- ``FoundationModelReasoningLevel``
- ``FoundationModelUseCase``

### Schemas

- ``FoundationModelsJSONSchema``
- ``FoundationModelsJSONSchemaError``
- ``RuntimeCompatibleGenerable``

### Tokens and Transcripts

- ``ModelTokenUsage``
- ``estimateTokens(from:)``
- ``estimateTokensConservative(from:)``

### Errors

- ``FoundationModelErrorProjection``
- ``FoundationModelsKitError``


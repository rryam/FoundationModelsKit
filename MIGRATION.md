# Migration to Foundation Models Framework Lab

FoundationModelsKit 2.x remains published from this repository. Active package
development now happens in
[Foundation Models Framework Lab](https://github.com/rudrankriyam/Foundation-Models-Framework-Lab)
so the app, command-line tools, evaluations, and reusable utilities share one
tested implementation.

## Who Needs To Migrate

No migration is required for applications pinned to a 2.x release. Existing
tags and the `FoundationModelsTools` product remain available here.

Move to the Lab dependency when you want the current transcript utilities,
context-budget fixes, history transforms, and tool updates.

## Package Dependency

Replace the standalone dependency:

```swift
.package(
    url: "https://github.com/rryam/FoundationModelsKit",
    from: "2.0.0"
)
```

with the active Lab package:

```swift
.package(
    url: "https://github.com/rudrankriyam/Foundation-Models-Framework-Lab.git",
    branch: "main"
)
```

## Products

The Lab package exposes two products:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(
            name: "FoundationModelsKit",
            package: "foundation-models-framework-lab"
        ),
        .product(
            name: "FoundationModelsTools",
            package: "foundation-models-framework-lab"
        )
    ]
)
```

- `FoundationModelsKit` contains lightweight transcript, token-counting,
  context-budget, text-content, and history-transform utilities.
- `FoundationModelsTools` contains the system and web tools and re-exports
  `FoundationModelsKit`.

Existing code that imports only `FoundationModelsTools` remains source
compatible. Add a direct `FoundationModelsKit` product dependency when an app
wants the lightweight utilities without permission-heavy system tools.

## Source And Issues

- Active source:
  [`Packages/FoundationModelsKit`](https://github.com/rudrankriyam/Foundation-Models-Framework-Lab/tree/main/Packages/FoundationModelsKit)
- Active issues:
  [Foundation Models Framework Lab issues](https://github.com/rudrankriyam/Foundation-Models-Framework-Lab/issues)
- Stable 2.x releases:
  [FoundationModelsKit releases](https://github.com/rryam/FoundationModelsKit/releases)

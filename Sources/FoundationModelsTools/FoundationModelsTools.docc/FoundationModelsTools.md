# ``FoundationModelsTools``

Ready-to-use Foundation Models tools for Apple platform capabilities and web services.

## Overview

`FoundationModelsTools` provides concrete `Tool` implementations that can be added to a `LanguageModelSession` or called directly from an app, command-line tool, or test harness. The product re-exports `FoundationModelsKit`, so importing `FoundationModelsTools` also makes the shared runtime and schema utilities available.

The tools preserve platform permission boundaries and surface typed errors instead of silently fabricating data:

- **Weather.** Fetch current weather for a city with ``WeatherTool``.
- **Web search.** Query Exa-backed search results with ``WebTool``.
- **Web metadata.** Extract title, description, and image metadata with ``WebMetadataTool``.
- **Contacts.** Search, read, and create contacts with ``ContactsTool``.
- **Calendar.** Create, query, read, and update events with ``CalendarTool``.
- **Reminders.** Create, query, read, update, and complete reminders with ``RemindersTool``.
- **Location.** Resolve current location, geocode addresses, reverse geocode coordinates, and calculate distances with ``LocationTool``.
- **Health.** Read authorized HealthKit data with ``HealthTool``.
- **Music.** Search and control Apple Music playback with ``MusicTool``.

## Topics

### Tools

- ``WeatherTool``
- ``WebTool``
- ``WebMetadataTool``
- ``ContactsTool``
- ``CalendarTool``
- ``RemindersTool``
- ``LocationTool``
- ``HealthTool``
- ``MusicTool``

### Web Services

- ``ExaWebService``


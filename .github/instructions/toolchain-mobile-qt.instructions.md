---
applyTo: "**/*.{kt,kts,cpp,cc,cxx,h,hpp,qml}"
description: "Stack-specific guardrails for Android/Kotlin/KMP and C++/Qt/QML codebases (loaded only on matching files)."
---

# Android / Kotlin / KMP & C++ / Qt / QML Guardrails

- **Android / Kotlin / KMP**:
  - Keep `android.*` and `org.jetbrains.compose.*` strictly out of `domain/`.
  - Close all `Cursor` instances via `.use { ... }` (`CursorLeak`) and invoke `notifyChange` after `ContentProvider` mutations.
  - Exclude pure formatters during inner-loop Gradle builds/tests (`-x spotlessCheck`); let `prepare-commit` run `spotlessCheck` once before committing.
- **C++ / Qt / QML**:
  - Keep `QQuick*` / `QtQuick` strictly out of `domain/`.
  - Always include `Q_OBJECT` on classes with `Q_PROPERTY` / `signals` / `slots` and declare `NOTIFY` signals on writable properties.
  - Use Qt 6 function syntax (`function onSignalName(...) { ... }`) in QML `Connections` blocks.

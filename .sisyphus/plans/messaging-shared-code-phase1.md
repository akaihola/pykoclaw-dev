# Refactor Shared Code to pykoclaw-messaging (Phase 1: Platform-Agnostic)

## Status: Backlog

## Priority: 1

## TL;DR

> **Quick Summary**: Move platform-agnostic code (images.py, segments.py, formatting utilities) from pykoclaw-matrix and pykoclaw-whatsapp into pykoclaw-messaging to eliminate duplication. These modules work as-is without modification.
>
> **Deliverables**:
>
> - `pykoclaw_messaging/images.py` - Image path detection (copy from matrix, works for WhatsApp)
> - `pykoclaw_messaging/segments.py` - Text/image segment splitting (copy from matrix)
> - `pykoclaw_messaging/formatting.py` - XML message formatting + `_extract_reply()`
> - Updated WhatsApp plugin to import from pykoclaw_messaging
> - Updated Matrix plugin to import from pykoclaw_messaging
>
> **Estimated Effort**: Low
> **Depends On**: —

---

## Context

### Current State

Both pykoclaw-whatsapp and pykoclaw-matrix have identical or near-identical code:

1. **`images.py`** - Both have `IMAGE_PATH_RE`, `detect_image_paths()`, `mime_for_path()` - completely identical
2. **`segments.py`** - Both have `ImageRef`, `TextSegment`, `ImageSegment`, `split_segments()` - completely identical
3. **`connection.py`** - Both have `_extract_reply()` - IDENTICAL
4. **format_xml_message/format_xml_messages** - IDENTICAL in both handler.py files

This duplication wastes effort - bug fixes require changes in multiple places, and it's unclear which version is canonical.

### Why This Matters

- **DRY principle**: Code should exist in one place
- **Maintainability**: Fix once, apply everywhere
- **Clarity**: Single source of truth for shared logic
- **Foundation**: Phase 2 builds on this shared infrastructure

### Technical Path

Copy the platform-agnostic modules from pykoclaw-matrix to pykoclaw-messaging, then update imports in both plugins. No logic changes needed - these modules have no platform-specific dependencies.

---

## Work Objectives

### Core Objective

Eliminate code duplication by moving shared platform-agnostic modules to pykoclaw-messaging.

### Must Have

#### 1. Create pykoclaw_messaging/images.py

- Copy from pykoclaw-matrix/src/pykoclaw_matrix/images.py
- Verify it works for WhatsApp file paths (absolute paths work the same)
- Exports: `IMAGE_EXTENSIONS`, `IMAGE_PATH_RE`, `detect_image_paths()`, `mime_for_path()`

#### 2. Create pykoclaw_messaging/segments.py

- Copy from pykoclaw-matrix/src/pykoclaw_matrix/segments.py
- Imports `IMAGE_EXTENSIONS`, `IMAGE_PATH_RE` from images.py
- Exports: `ImageRef`, `TextSegment`, `ImageSegment`, `Segment`, `split_segments()`

#### 3. Create pykoclaw_messaging/formatting.py

- Copy `_extract_reply()` from either plugin (they're identical)
- Copy `format_xml_message()` and `format_xml_messages()` from either plugin
- Exports: `_extract_reply()`, `format_xml_message()`, `format_xml_messages()`

#### 4. Update pykoclaw-messaging/**init**.py

- Add exports for new modules

#### 5. Update pykoclaw-whatsapp imports

- In connection.py: import `_extract_reply` from pykoclaw_messaging
- In handler.py: import formatting functions if needed

#### 6. Update pykoclaw-matrix imports

- In connection.py: import from pykoclaw_messaging.images, segments, formatting
- Remove local images.py, segments.py files (or deprecate)

### Verification

- [ ] `python -c "from pykoclaw_messaging import images, segments, formatting"` works
- [ ] WhatsApp plugin runs and processes messages normally
- [ ] Matrix plugin runs and processes messages normally
- [ ] Image detection works in both plugins (test with a file path in message)

---

## Dependencies

None - this is a pure refactor with no external changes.

---

## Notes

- The files are literally copy-paste identical or nearly so - no adaptation needed
- Matrix's images.py is slightly more complete (has `mime_for_path`) - use that version
- After this, Phase 2 can parameterize BatchAccumulator and DB functions

# Visual representations

This folder contains reusable visual representations of domain entities.

A domain entity is not a card. The same CWP, radio, telephone, recorder or player may appear with different information density depending on the screen.

## Current variants

- `cwp/`: Full, Summary, Thumb, ListItem
- `radio/`: Pill, PillList, Summary
- `telephone/`: Pill, PillList, Summary
- `recorder/`: Full, Summary, Status
- `player/`: Mini, Inline

Features and views choose the representation appropriate to their context. They should not recreate a new CWP/Recorder/Radio visual locally unless it is genuinely feature-specific.

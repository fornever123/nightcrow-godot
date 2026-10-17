# Nightcrow Godot project

Use Godot 4.7.2 and GDScript. This directory is independent of Maker; never invoke Maker tools or preview/build pipelines here.

User art comes only from the E-drive Nightcrow character and associated feather slash. Keep source images unchanged; edits/imports create new assets. Do not use image/video generation unless the user changes this instruction.

Combat comes from the C-drive player/dummy/projectile implementation. Author tuning in assets/data/battle.json; configuration.gd derives animation-matched physical timings. Keep input buffering before per-actor hitstop. The main editor is tools/battle-editor, based on the E-drive Vue/Pixi app.

Only character and wooden dummy in the training scene. Do not add enemies, background art or extra gameplay unless requested.

Read docs/开发交接.md before changes. Use tests/test_training.gd for mechanics; tests/test_editor.mjs exercises editor/game integration and restores its changes. Inspect actual rendered images before art claims. User instructions take priority.

## GitHub version control

This folder is an independent Git repository. Its GitHub origin is fornever123/nightcrow-godot (public by user request), separate from the parent Maker repository. Scope staging and commits to this folder. Do not change the parent remote or upload parent files. Use tools/github-sync.ps1 for user-requested GitHub updates; never force-push or overwrite unfinished merge/rebase work. Keep engine binaries, caches, backups and credentials excluded. See docs/GitHub更新说明.md.

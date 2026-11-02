# Nightcrow Godot project

**Before doing anything, read `docs/项目进程.md`.** It is the single source of truth for project progress and the user's latest requirements. Newer requirements override older ones. After every step of work, update it: add an entry at the top of its 进程记录, update that line's status, and put new user requirements at the top of 最新要求. Do not create separate handoff documents.

Always reply to the user in Simplified Chinese.

Engine: Godot 4.7.2 (`engine/Godot_v4.7.2-stable_win64_console.exe`), GDScript, Forward+ renderer. This directory is independent of TapTap Maker; never invoke Maker tools or Maker preview/build pipelines here.

Several work lines (background, lighting/FX, ultimate, rain trial, audio) share this working tree. Only edit files owned by your line; see `docs/项目进程.md` §4.

## GitHub version control

This folder is an independent Git repository. Its GitHub origin is fornever123/nightcrow-godot (public by user request), separate from the parent Maker repository. Commit only when the user asks, and keep commits scoped to one work line. Use `tools/github-sync.ps1` for user-requested GitHub updates; never force-push or overwrite unfinished merge/rebase work. Keep engine binaries, caches, backups and credentials excluded. See `docs/GitHub更新说明.md`.

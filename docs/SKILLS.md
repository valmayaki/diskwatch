# Agent skill

`skill/diskwatch/` is an [Agent Skill](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview):
a packaged set of instructions, a script and reference notes that teach an AI coding
assistant (Claude Code, the Claude apps, or any agent that loads `SKILL.md` folders) how to
analyse disk usage with diskwatch, quickly and without causing damage.

## Why a skill

Disk analysis is easy to get subtly wrong. An agent left to `du`/`find` walks the disk for
minutes, double-counts APFS clones, wanders into the firmlink loop, or suggests deleting
something important. The skill makes the agent:

- answer from the cached index first (seconds instead of minutes);
- start every investigation with a one-shot overview;
- know which numbers to distrust and why (clones, swap, snapshots, cloud placeholders,
  APFS reserves, thin provisioning);
- separate "safe to clear" from "needs your decision", and **never delete without explicit
  confirmation**;
- rescan only when the index is stale, in the background, with progress reporting.

## Contents

```
skill/diskwatch/
  SKILL.md                     when to use it, workflow, scanning, how to read the numbers
  scripts/overview.sh          read-only health overview from the index (≈ 10 s, macOS)
  references/macos-gotchas.md  accounting pitfalls, safe vs unsafe cleanup, tool traps
  references/linux.md          servers: storage/cleanup/pkgs, thin pools, kernels, deployment
```

Only `SKILL.md`'s front-matter (name and description) is always loaded; the body, script and
references load when a request matches, so the skill costs almost nothing in unrelated
conversations.

## Install

Claude Code (personal skill, all projects):

```sh
mkdir -p ~/.claude/skills
cp -R skill/diskwatch ~/.claude/skills/
```

Project skill: copy it to `<project>/.claude/skills/diskwatch` instead. For other agents,
point them at the folder or include `SKILL.md` in their instructions. The skill expects
`diskwatch` on `PATH` (see [INSTALL.md](INSTALL.md)).

## Using it

Ask in plain language; the description triggers the skill:

- "Why is my disk full?" / "What grew since yesterday?"
- "Which apps haven't I used in three months?"
- "How much space does iCloud take locally?"
- "Our Proxmox host is at 95 %, what can we clean up?"
- "Schedule disk scans for Sundays at 2 am."

A typical run: `scripts/overview.sh` → `diskwatch ls` / `du` on the biggest items →
`diskwatch report` for growth → a short answer with sizes, sources, safe actions and exact
commands, deletions left to you.

## The overview script

`scripts/overview.sh [--brief]` reads only the index, `df` and `diskutil`:

| Section | Source |
|---|---|
| Free space (local volumes) | `df` |
| APFS volumes and reserves in the internal container | `diskutil apfs list` |
| Index age and roots | `duc.db`, `diskwatch roots` |
| Largest in `/` and `~` | `diskwatch ls` |
| Common space hogs (caches, Xcode, simulators, Android SDK, Ollama, Docker, Homebrew…) | `diskwatch du` |
| Growth since previous scan | `diskwatch report` |
| Cloud drives | `diskwatch cloud` |
| Large apps unused ≥ 90 days | `diskwatch apps` |

## Customising

- Add your own space hogs to the `diskwatch du` list in `scripts/overview.sh`.
- Add environment notes (hosts, how to reach them, deployment commands) to a private copy of
  `references/linux.md`; keep host names out of public copies.
- Keep `SKILL.md` short; put detail in `references/` and link it from `SKILL.md` so the
  agent knows when to read it.

## Validating changes

Skills are validated by structure (front-matter with `name` and `description`, referenced
files present). With Anthropic's skill-creator scripts:

```sh
python3 path/to/skill-creator/scripts/quick_validate.py skill/diskwatch
```

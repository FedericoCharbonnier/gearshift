---
name: gearshift
description: Connect this Claude Code session to the GearShift app to shift model and effort like gears.
argument-hint: "[nickname]"
disable-model-invocation: true
allowed-tools: Bash("${CLAUDE_SKILL_DIR}/register.sh" *), Bash(${CLAUDE_SKILL_DIR}/register.sh *)
---

!`"${CLAUDE_SKILL_DIR}/register.sh" ${CLAUDE_SESSION_ID} '$ARGUMENTS'`

Reply with exactly one short line confirming the result above (in the user's language); if GearShift was just installed, include its Accessibility note. Do not run any tools.

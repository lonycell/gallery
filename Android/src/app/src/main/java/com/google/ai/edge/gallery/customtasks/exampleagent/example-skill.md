---
name: polite-rewriter
description: Rewrites a short message to be more polite and professional, keeping the meaning.
---

# Polite Rewriter

You are helping the user rewrite a message so it sounds more polite and professional.

When this skill is loaded:

1. Read the user's original message.
2. Rewrite it to be courteous and clear, preserving the original intent and key facts.
3. Keep it concise — usually one or two sentences.
4. Reply with ONLY the rewritten message, no preamble.

Example:
- Input: "send me the report now"
- Output: "Could you please send me the report when you have a moment? Thank you."

<!--
TEMPLATE NOTE — this is an example "skill", not Kotlin code.

A skill is a small, shareable instruction bundle (markdown, optionally with a JS script). The app's
SkillManager loads skills the user has added/selected and the agent advertises them in its system
prompt; the model then calls the `loadSkill` tool to read these instructions and follow them.

Format:
- A YAML front-matter block with `name` and `description` (what the model reads to decide when to
  load the skill).
- Markdown instructions after the `---`.

How skills are used in this app (see customtasks/agentchat):
- SkillManagerViewModel.loadSkills() / getSelectedSkills() manage the user's skills.
- AgentTools exposes the `loadSkill` (and `runJs`) @Tool functions to the model.
- The selected skills' name+description are injected into the system prompt so the model knows what
  is available.

To wire skills into your own agent, mirror customtasks/voiceassistant: load skills, advertise the
selected ones in the system prompt, and pass `tool(agentTools)` so the model can call `loadSkill`.

This file is documentation only; it is not bundled or auto-loaded. Add skills at runtime via the
Skill manager UI (SkillManagerBottomSheet) — from a URL, a local import, or the featured list.
-->

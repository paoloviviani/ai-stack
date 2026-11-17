# Permission model: open design notes (2026-11-04)

Not a decision. Collected while the owner decides how ADR 0105's auto mode and the machine ceiling should work.

## Owner's notes (verbatim intent)

- With a decision model and auto mode: "I don't want to see any request unless an escalation is called, not even external directories."
- Streamline the ceiling: too many categories; delegation should be one.
- Give users the full spectrum, from most control to fully hands-off, with each step saying clearly what requests the user will receive.
- No sandbox assumptions (an OS-level sandbox is not coming soon).
- The decision model's system prompt is editable by the admin, on a dedicated admin screen; the admin chooses the decision model.
- **"Writes elsewhere (~, /etc) stay with you" is not what the owner wants.** They want a *true* auto mode they can rely on for hands-off work on a headless machine: if the agent needs to edit e.g. Docker daemon settings in /etc (even with sudo), the decision model checks and allows, or the owner can allow that class. Not for everyone, but the owner is the first user and wants to replicate the Claude Code experience.

## Advisor (Fable) proposals

1. Patched model: a new ceiling word `review` ("a check is required": a person, or the reviewer in Auto; refused under skip); Auto = Allow on the machine + a reviewer for the residual cards (degrades to Allow); 3 UI steps over 4 wire words (`deny < ask < allow < auto`); six ceiling categories (shell, files, outside, web, agents, tools) with a min-over-members migration; admin-editable reviewer text inside a fixed frame (fencing last, output contract, threshold floor 0.80, length cap) and a save-time canary over the trial cases.
2. One-table model: one answerer axis `refuse < person < reviewer < nobody`; galopin classifies each ask (read/edit-in-project, command, web, outside-read/write, secrets, agent-config, agents, tools, loop); `answerer = min(machine limit[class], session preset[class])`; presets Plan · Ask · Auto · Hands-off; skip = Hands-off machine-wide; the UI computes the expectation line per machine. ~1 week galopin + 2–3 days Cerea; migration on load, no re-enroll.

## Orchestrator notes on the owner's headless requirement

- Fits the one-table model if the per-class limits are machine choices: the owner's headless machine enrolls with every class at `reviewer` (commands incl. sudo, outside writes, secrets…); other machines keep conservative defaults.
- One structural floor proposed regardless: the agent never writes galopin's own policy/config (otherwise it can raise its own limits); everything else may go to the reviewer where the machine's owner chooses.
- sudo needs non-interactive sudo for the agent's account (machine setup, outside galopin).
- Re-run the reviewer trials with instructions written for unattended system administration before setting that machine's threshold (the 2026-11-04 trial instruction told the model to refuse anything outside the workspace).

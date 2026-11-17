# ADR 0104: Connector enablement in one place, tools loaded on demand

- Status: ACCEPTED (owner, 2026-10-27)
- Context: Cerea chat; MCP connectors (ADR 0064), local connectors (ADR 0102)

## Context
Connectors are chosen per chat from the composer's + menu, and the choice is kept in the browser. This applies to the deployment's `.env` servers, the administrator's connectors, and the person's own. As deployments add connectors (search, maps, more), two problems grow:
- **Clutter:** people are asked to choose tools they should simply have.
- **Cost:** every selected connector's full tool definitions go into every request. The prompt gets longer, and the model chooses less well.

## Decision
1. **Turning connectors on and off happens in one place: Workspace → Connectors.** The composer no longer offers connector choices, and there is no per-chat selection. People who want a connector off turn it off in Workspace.
2. **Deployment connectors** (`.env` and the administrator's) have an administrator-set mode, managed in Admin → Connectors:
   - **Off:** offered to nobody.
   - **On:** on for everyone by default; a person may switch it off in Workspace.
   - **On, locked:** on for everyone, and people can't switch it off.

   The default for existing and new deployment connectors is **On**.
3. **Personal connectors** are switched on and off in Workspace. A personal connector that needs sign-in shows its sign-in state there.
4. **"On" means available, not loaded.** Each turn, the model gets:
   - the **core built-ins, fully loaded**: web search and fetch, code, document tools, plan, ask the person, delegate and research, artifacts and memory;
   - **one line per enabled connector**: its name, a short summary and its tool names;
   - a built-in `load_tools` that takes one or more connector names and makes their tools callable.

   Loaded connectors **stay loaded for the rest of the conversation** (stored on the conversation), so the request prefix is stable and prompt caching keeps working. Newly loaded tools are appended after the existing ones.
5. **An administrator may mark a deployment connector "always loaded"** to skip the load step. The default is off.
6. **The catalogue line comes from a cached tool listing.** Connector rows already store their tool names from the last check. A turn doesn't contact every enabled connector just to build the list; it contacts a connector only when that connector is loaded or called.
7. **Everything resolves on the server.** A single resolver decides which connectors a turn may use, from the modes, the person's Workspace switches and the conversation's loaded set. Every path uses it: the turn, the approval and parked-turn resumes, helper agents and delegate (which inherit the catalogue and the loaded set). Browser state can't widen or narrow it.
8. **Approval policy is unchanged.** Loading a connector is not an approval; calling its tools asks exactly as before.
9. **Project connector defaults** (`defaultMcpConnectorIds`) are retired, since per-chat selection no longer exists. Revisit this if projects need their own connector set; that would be a project-level switch list, not a per-chat one.

## Consequences
- **Behaviour change on upgrade:** every deployment connector becomes On for everyone, and a person's old browser choices no longer apply. The release note tells administrators to review Admin → Connectors.
- **First use costs one step:** the model loads a connector's tools, then calls one, once per conversation per connector. Weaker models may not think to load. Mitigations: clear one-line summaries, skills that say what to load, and "always loaded" for critical connectors.
- **Measurement:** tool-definition tokens per turn are logged before and after, so the saving is shown rather than assumed.
- Provider-native tool search (Anthropic's) isn't used, because the gateway serves many providers. This design works with any model that can call tools.

# Open-source release checklist

Steps that happen when the user decides to make the repositories public. Nothing
here is done before that decision.

## Per repository, when it goes public (Cerea, Pystino, cerea-deploy)

- [ ] Visibility → Public (the user's call, per repository).
- [ ] **Settings → Code security → Private vulnerability reporting: enable.**
      Both `SECURITY.md` files send reporters to the Security tab's "Report a
      vulnerability", which GitHub offers only on public repositories with this
      setting on.
- [ ] Check the README renders on GitHub (links, the screenshot, tables).

## Shared

- [ ] Publish the images to GHCR (the image workflows are held at `workflow_dispatch`).
- [ ] Re-pin cerea-deploy to the release tags with `tools/pin`.
- [ ] Pystino's tag-time drift guard: add the `CEREA_DEPLOY_TOKEN` secret (read-only,
      cerea-deploy contents) and grant the Cerea package Actions access to Pystino,
      or drop the secret once cerea-deploy is public.

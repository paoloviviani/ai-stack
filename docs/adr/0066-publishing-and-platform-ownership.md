# 0066 — Shared with everyone, and owned by the platform

- Date: 2026-09-11
- Status: **accepted, built.** The predicate, `administers`/`may_unpublish`,
  the share and unshare routes for knowledge bases, the erasure guard and
  migration 0032 are done, tested and applied to a live PostgreSQL. Agents
  reuse the predicate but have no publish route yet, and the console half is
  separate work.
- An earlier draft claimed to be built when no code existed, and carried a
  table of eleven mutation results for tests that had never run. The table
  below is the one that *was* run — seven faults, one of which survived and is
  recorded as such.
- Asked as a correction to a half-answer: *"the public/everyone is fine, but
  it's half of the story: a user should be able to make a custom agent or a kb
  shared to everyone, but they will keep the ownership. Admin-defined public
  KBs should be shared to everyone, but owned by the platform."*
- Extends [ADR 0062](0062-knowledge-bases.md), whose ACL this is. Inherits the
  credential rule it established for `/v1/knowledge/config`, and the
  `may_reach` bug it records, which the verification plan at the end is
  shaped around.

## Two things, and they are genuinely two

The request separates a mechanism from a policy, and the separation is the
whole design.

**Publishing** is a *grant*: a user shares their own resource with everybody
and stays its owner. Nothing about the resource changes. They can still edit
it, still delete it, still see it listed as theirs, and withdrawing the grant
puts it back exactly as it was.

**Platform ownership** is an *absence of owner*: a knowledge base belongs to
the deployment rather than to a person, so that the organisation's corpus does
not leave when the administrator who built it does. It is administered, not
owned.

They compose — an admin-defined public base is a platform resource with an
`everyone` grant on it — but they are independent, and conflating them is the
mistake the question was correcting. A user's published base is *not* the
platform's, and a platform base is *not* automatically public.

## How "everyone" is expressed, and why not the other two

`SharePrincipal.EVERYONE`, a third principal kind, with `principal_id` fixed at
the **nil UUID** because that column is part of the composite primary key and
cannot be null. `uuid4` cannot produce the nil UUID, so the sentinel can never
collide with a real user or group id — which is what a magic value in a
foreign-key-shaped column normally gets wrong.

**A boolean column on the resource** was the obvious alternative, and
`ModelDef.is_public` is the precedent for it (ADR 0027/0045): a column
predicate beside the grant EXISTS clauses, cheaper than a fourth EXISTS, and
already proven in `access.py`. It is wrong here for three reasons, in the order
that decided it.

1. **One of the three shareable kinds has no row in this database.**
   `chat_project` lives in the chat's MongoDB and shares through
   `resource_shares` precisely so that "who may see this" has one
   implementation. There is no table here on which to put its flag, and
   `reachable()` takes its caller's own columns — a `public_column` parameter
   would have nothing to pass for that kind.
2. **A boolean has no role.** Publishing as `viewer` and publishing as
   `editor` are different acts, and the grant row already carries the
   distinction the rest of the ACL is built on.
3. **A boolean has no provenance.** `granted_by` and `created_at` are how an
   administrator answers "who published this, and when" about something the
   whole deployment can suddenly read. A flag answers neither, and this is
   exactly the class of fact ADR 0033 and ADR 0048 added append-only rows to
   keep.

**A reserved id under the existing `group` kind** — an "everyone" pseudo-group
— was rejected faster. It puts an id into `principal_id` that is not in
`groups`, so `list_shares`' join to name the principal returns nothing,
`resolve_principal` needs a special case anyway, and every future reader that
treats a group-kind row as a group id is wrong in a way that reads as correct.
A pseudo-group nobody is a member of is a worse lie than a new kind.

The cost of the kind, stated plainly: `reachable()` gains a fourth EXISTS which
is **unconditional**, since there is no caller-side predicate to gate it on.
That is also its trap — the `everyone` clause is the only one reachable by a
caller the function knows nothing about, so it is the easiest to forget and the
only one whose absence is silent.

## How platform ownership is expressed, and the `SET NULL` trap

`knowledge_bases.owner_user_id` and `agents.owner_user_id` become **nullable**,
and null means the deployment owns it.

**A seeded "platform" user** to own them was written first and is worse in a
way that only shows up later: a fake person appears in the user listing, in
membership queries, in every quota scope, in the group-sync path, and in
`DELETE /api/admin/users/{id}`, where an administrator can delete it. Twenty
places would need to know it is not a person.

**A boolean beside a non-null owner** keeps a person's id on a row the
deployment owns, which means two sources of truth for "may this person delete
this" and one of them wrong.

The part to read before touching the schema is the **foreign key, which stays
`CASCADE`**. `ON DELETE SET NULL` is the natural spelling for a column that has
just become nullable, and here it is a data-protection bug: it would silently
promote every erased person's private corpus into a platform base that
administrators can read, at the exact moment that person exercised their right
to be forgotten. With `CASCADE` kept, null is only ever written **deliberately**,
so the column has exactly one meaning and "ownerless" and "erased" can never be
confused. Erasing a user still takes their bases and agents with them, as
before.

Note also what null *used* to mean in this code. Before this ADR,
`reachable()`'s empty-case fallback was spelled `owner_column.is_(None)` —
"nothing can match", true because the column was `NOT NULL`. Making it nullable
turned that same expression from *no rows* into *every platform resource*. The
branch is deleted rather than left standing beside its own negation; the
expression now appears once, as the administrator clause, meaning the opposite
of what it used to.

**A file is never platform-owned.** `files.owner_user_id` stays `NOT NULL`.
Sharing happens on the base so that "who can read this document" has one
answer, and an ownerless file would be a second one.

## May an administrator publish somebody else's resource? No

Decided, justified, and enforced by `sharing.administers`, which is the only
place either router asks.

There is **no administrator read access to a private knowledge base anywhere in
this gateway** — `_reachable_base` has never had a backdoor and does not gain
one here. A publish right over a resource they cannot open would therefore be a
way to disclose a colleague's documents *without ever being able to see what
they were disclosing*. That is a strictly worse capability than reading, and it
would have been invented by the sharing surface rather than by any decision
about administration.

The asymmetry that follows is deliberate: **an administrator may take a
publication down, on anything.** Unpublishing removes reach; publishing adds
it. An operator must be able to remove something from the whole deployment
without deleting somebody's work to do it, and they can see it to act on —
a published base is in their listing like everybody else's. Every *other* grant
on a resource they do not own stays out of reach, including the personal share
sitting beside the publication they just withdrew.

`is_admin` therefore buys exactly one thing in the predicate:
`owner_user_id IS NULL`. Not "administrators see everything" — a colleague's
private base is as invisible to an administrator after this ADR as before it,
and `test_an_administrator_reaches_the_platforms_base_and_not_a_persons` is the
test whose whole job is to keep that true.

## Creating a platform resource needs a person, not a key

The same rule ADR 0062 established for `/v1/knowledge/config`, and the same
reasoning: an API key is refused even when its owner is an administrator. A key
is what a program holds, often in a config file; an access token is evidence
that a person signed in minutes ago. Creating something that carries the
organisation's name and outlives its author is an act on the deployment's
behalf.

**Publishing your own resource needs neither check.** It is a decision about
your own content, made with your own credential, and requiring a browser
session for it would mean the chat could not offer the feature to a program at
all.

## Erasing somebody who published

Their bases and agents are `CASCADE` and go with them — correctly, since they
are that person's content, and that is ADR 0062's position unchanged. But a
*published* resource has an unbounded and unknowable set of people relying on
it, and removing it as a side effect of an unrelated administrative act is how
a deployment loses a corpus nobody realised was one person's.

So `DELETE /api/admin/users/{id}` **refuses while the account owns anything
shared with everyone**, and names it — "the knowledge base 'the handbook'", not
"2 resources", because a count sends an administrator hunting through a listing
where somebody else's published base appears under its own name and nothing
marks it as theirs.

This is **not a block on erasure**, which would be a compliance bug rather than
a safeguard. Unpublishing it, or transferring it to the deployment, takes one
call and then the erasure succeeds. A base shared with three *named* colleagues
still cascades away: those people are identifiable and can be told, so only the
unbounded case is refused. That line is deliberately where it is, and
`test_a_privately_shared_base_does_not_block_erasure` exists to stop the guard
quietly widening into "any share blocks erasure", which would leave an
administrator unable to complete an erasure request at all.

## A platform base still has a billing group

Ownership and who pays are different questions, and this is the row where they
visibly diverge. A platform base carries `billing_group_id` — the creating
administrator's group — because indexing costs money and a corpus nobody is
charged for is spend that appears in no report (ADR 0062's fourth reason for
putting knowledge bases in the gateway at all).

That leaves the *user* half of the quota subject with nobody to name, since
`Principal` requires a user and `_metered` bills against a `(user, group)`
pair. `Ingestor._billing` therefore falls back to **whoever asked for the
work** when there is no owner, which is why `spawn` and `billing_for` now take
an actor. The group half does not move, so ADR 0062's rule — an admin pressing
"reindex" does not move somebody else's spend onto their own budget — still
holds where it costs money. What changes is only which person's per-user
ceiling engages, and the alternative was the fake user row rejected above.

## Reproducing the fault, seven times — and the one that survived

ADR 0062 records that fourteen tests passed against an `or_` where an `and_`
belonged, because every negative one failed closed for an unrelated reason.
Each fault below was reintroduced alone and the suite run against it.

**Six were caught. The seventh was not, and it is the most valuable line in
this document.** Removing the `is_admin` check from `may_reach` — leaving it in
`reachable` — handed every signed-in person read access to every unpublished
platform base. The listing correctly showed nothing while the single-resource
path that `GET /v1/knowledge/bases/{id}` uses returned it: invisible in a list
and openable by id, which is the worst shape the bug could take. `reachable`
and `may_reach` answer the same question by different routes and are written
separately, so a check added to one is not added to the other;
`test_a_platform_base_is_not_reachable_by_an_ordinary_caller` exists solely
because that mutation survived.

The faults, with what caught them:

| Fault | Caught by |
|---|---|
| `resource_id` dropped from the `everyone` EXISTS | `test_publishing_one_base_publishes_exactly_that_base`, `test_publishing_as_a_viewer_does_not_hand_out_editing` |
| `role` dropped from the `everyone` EXISTS | `test_publishing_as_a_viewer_does_not_hand_out_editing` |
| administrator clause widened to `literal(True)` | `test_an_administrator_reaches_the_platforms_base_and_not_a_persons` |
| `if owner_user_id is None` without `and is_admin` | `test_a_platform_base_is_not_everybodys_until_it_is_published` |
| `administers` returning `... or is_admin` | `test_administering_is_ownership_or_the_platform_and_nothing_else` |
| `_administers` short-circuiting on `is_admin` at the route | `test_an_administrator_cannot_publish_somebody_elses_base`, `test_an_administrator_may_take_a_publication_down_and_nothing_else` |
| takedown widened to any principal kind | `test_an_administrator_may_take_a_publication_down_and_nothing_else` |
| API-key refusal removed from `require_platform_author` | `test_a_platform_base_needs_an_administrator_who_signed_in` |
| owner foreign key changed to `SET NULL` | `test_a_platform_base_outlives_the_administrator_who_made_it`, `test_a_privately_shared_base_does_not_block_erasure` |
| erasure guard widened to any share | `test_a_privately_shared_base_does_not_block_erasure` |
| erasure guard removed | `test_erasing_a_publisher_is_refused_until_it_is_unpublished`, `test_a_published_agent_blocks_erasure_too` |

Every negative assertion in the new tests is paired with a positive one **on
the same data**, which is what makes that table mean anything: a 404 that
happens because there was nothing to find proves nothing about the predicate
that produced it.

## What was found while building it

- **The bearer path re-derives `is_admin` from the token on every request.**
  `admin_groups` defaults to `platform-admins`, so a test that set `is_admin`
  on the row and then authenticated with a token not carrying that group got a
  403 that looked like a policy bug and was ADR 0057 working correctly. It is
  recorded here because the failure names the wrong thing: the message says
  "only an administrator", and the account *is* one in the database.
- **`_billing` could not have stayed as it was.** It took the owner out of the
  base and resolved a `User` from it; with a null owner it raised "the owner of
  this knowledge base no longer exists" on a base whose owner was never a
  person. Threading the actor through `spawn` was not optional, which is why
  the ingestion signature changed in an ADR that is nominally about sharing.

## Consequences

- **The `everyone` grant needs no DDL.** `principal_kind` is an `_enum` column
  — VARCHAR with no CHECK — chosen so a new value is not a locking migration,
  the same property that let `limit_rules.metric` gain a value in 0031.
  Migration 0032 is two `DROP NOT NULL`s and nothing else.
- **Nothing is backfilled and nothing moves.** Every existing row keeps its
  owner and gains no grants, so no resource becomes visible to anybody who
  could not already see it.
- **The downgrade destroys data and says so.** Rows with a null owner cannot
  satisfy `NOT NULL`, and assigning them to an arbitrary administrator would
  hand one person the organisation's corpus. It deletes them and every
  `everyone` grant, and prints what it removed.
- **`owned` and `role` disagree on exactly one shape.** An administrator on a
  platform base has `owned: false` and `role: "owner"`: they administer it,
  they do not own it, and a client that wants to say "yours" should not say it
  about the organisation's corpus. Every other shape agrees.
- **`shared_with_everyone` is on the object rather than inferred.** A viewer
  cannot otherwise tell "somebody shared this with me" from "this is public",
  and the listings resolve it for every row in one query
  (`sharing.published_ids`) rather than the N+1 the first version had.
- **Publishing an agent publishes no documents.** Retrieval still re-checks the
  caller's own access to every attached base per request (ADR 0062), so an
  agent the whole deployment can call, over a private base, answers from
  nothing for everyone but the people who can read the base. The feature that
  stops an agent lending out a document did not need changing, which is the
  best evidence that it was in the right place.
- **A platform base is invisible until it is published.** Owned by the
  deployment is not the same as readable by the deployment; the admin-defined
  public base is two acts, and the second one is a grant like any other.

## Still to build

- **The console half.** Both admin consoles need it, and the split is
  ADR 0062's: publishing a base you own is a chat-side control beside the
  existing share dialog; creating a platform base and taking a publication down
  are gateway-console screens, because they are operator acts.
- **Transferring an existing resource to the platform.** The erasure refusal
  names it as one of the two ways out and there is currently only one — an
  owner must unpublish. A transfer is a one-column write and an owner-or-admin
  policy question that has not been asked yet, so it is not guessed here.
- **`chat_project` publishing.** The kind is already in the table and the
  predicate already serves it; whether a project should be publishable at all
  is the chat's decision, not this one's.

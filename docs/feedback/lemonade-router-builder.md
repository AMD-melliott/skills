# Feedback — `lemonade-router-builder`

**Reviewer:** Matt Elliott
**Date:** 2026-08-11 (initial pass — desk review, live testing pending)
**Reviewed at:** `amd/skills` @ `cf5e518`
**Hardware:** AMD Strix Halo (gfx1151), 128 GB unified memory, XDNA NPU, Pop!_OS 24.04
**Lemonade:** `lemonade-server 11.5.2~24.04` (PPA), system `lemond.service`, `:13305` healthy

> **Status of this document.** Everything in §1 and §2 is a desk review of
> `SKILL.md`, `reference.md`, `examples.md`, and `scripts/validate.py` against a
> live 11.5.2 server and a production local-inference stack. Items marked
> **[unverified]** are hypotheses that the test plan in §4 is designed to settle.
> They are flagged rather than asserted.

---

## Reviewer context

Relevant because it shapes what I noticed and what I missed. This box runs a
multi-slot Lemonade stack in daily use:

```
:13305  proxy
  :8001  Qwen3-Embedding-0.6B-Q8_0     llamacpp/vulkan   embedding:1
  :8002  bge-reranker-v2-m3-Q8_0       llamacpp/vulkan   reranking:1
  :8003  Qwen2.5-VL-7B-Instruct-Q4_K_M llamacpp/vulkan   llm:1 (+ mmproj)
```

It also already runs **three** other routing layers, which is the lens I read
this skill through:

| Layer | Routes on |
|---|---|
| `claude-code-router` `Router` block | request class (default / background / think / longContext + token threshold) |
| litellm (Nomad) | model name → provider |
| `mtctl resolve` (own control plane) | model registry + GPU-arbiter state + slot readiness |
| **`collection.router`** | **prompt content** — keywords, regex, length, images, tools, metadata, classifiers |

`collection.router` is the only content-aware layer of the four. That is a real
differentiator and the skill should lean into it harder than it currently does.

---

## 1. What works well

### 1.1 The mode fork is the right first decision, and it is enforced

Making "LLM-as-router vs. rules" the *first* thing the skill decides — with a
concrete trigger ("the user names any concrete signal") rather than a vibe — is
good design. Better still, the skill enforces mutual exclusivity three separate
times (the table note, Step 4's all-caps warning, and the defaults summary). For
a schema violation the server rejects outright, that redundancy is earned rather
than padding.

### 1.2 The prompt-authoring guidance is the most valuable content here

Step 4's explanation that the engine **unconditionally appends its own JSON
reply contract** — and that authoring "reply with ONLY the model name" therefore
causes weaker judges to emit a bare string, fail the parse, and silently fall
back to `default_model` — is exactly the kind of thing that costs a user a day
and cannot be discovered by reading the schema. The good/bad prompt pair makes
it concrete, and the explicit banned-verb list ("pick", "output", "reply with",
"respond with") makes it checkable.

The same reasoning is correctly repeated for `type: "llm"` classifiers in Step 5
rather than left as an exercise. Good.

### 1.3 Scope discipline

"Generates and validates the JSON only — does not register it or call the live
server" is stated in the frontmatter, restated in the opening paragraph, and
enforced in Step 8b ("Do not execute these with Bash or any tool — print them as
text only"). A skill that knows what it is *not* is rarer than it should be.
This also keeps it testable offline, which is why §4's T1 costs 30 minutes
instead of a day.

### 1.4 The offline validator as a hard gate

`scripts/validate.py` (512 lines, stdlib-only) plus "do not present a policy that
fails this check" converts the deterministic part of the task into a script
instead of trusting the model. This matches CONTRIBUTING's "lean on scripts for
the deterministic parts" and is the single biggest reliability lever in the
skill.

### 1.5 Small footguns named explicitly

Several of these are the sort of thing only someone who has been bitten
documents:

- `/pull` is idempotent per `model_name`, so a second policy under the same name
  silently overwrites the first — hence the derived-name guidance and the
  "don't reuse a name from earlier in this conversation" rule.
- `keywords_any` is case-insensitive **substring**, so `"hi"` matches inside
  `"shipping"`. The pointer to `regex` with `\b…\b` is the right fix.
- Rule order is first-match-wins, with the privacy-before-topic example
  ("a 'sensitive stays local' rule must precede a 'code goes to the big model'
  rule, or coding prompts with PII leak"). Naming the failure, not just the
  rule, is what makes it stick.
- `semantic_similarity` rejects a `labels` key because concept names *are* the
  labels — a non-obvious asymmetry with the other two classifier types.

### 1.6 Defaults table

The Step-by-step body and the defaults summary agree with each other, and the
table gives the agent a single place to resolve "user didn't say." This is the
part of the skill most likely to keep two runs consistent.

---

## 2. What needs improvement

Ordered by impact.

### 2.1 HIGH — Nothing about slot contention or load latency

This is the biggest gap, and it is the first thing a real multi-slot user hits.

A policy names N candidates. A Lemonade host has a bounded number of slots — on
this box, one `llm:1` occupied by a 7B vision model, with embed and rerank
coresident. The skill never says what happens when the router picks a candidate
that is not currently loaded:

- Does lemond auto-load it?
- Does it evict the current `llm:1` occupant?
- What is the added latency on the routed request — and does the router's own
  judge call (Mode A) contend for the same slot as the candidate it selects?
- Can a two-candidate policy thrash the slot on alternating requests?

**Why it matters beyond this box:** a user who authors a perfectly valid
three-candidate policy on a laptop will see p99 latency that looks like a bug.
The skill's whole value proposition is "the JSON is accepted on the first try" —
but accepted-and-valid is not the same as *operationally sane*, and right now
the skill implies the former guarantees the latter.

**Suggested fix.** Add a short "Step 3a — candidates and slots" note, and one
row to the defaults table:

> **Candidates share the host's model slots.** Every candidate the router may
> pick has to be loadable in the LLM slot. If two candidates cannot be resident
> at once, alternating traffic will pay a model-load cost on each switch. Prefer
> 2–3 candidates that are either coresident or cheap to swap, and put the
> highest-traffic one in `default_model`. In Mode A, the `router.model` judge
> also occupies a slot — making it one of the candidates avoids a third
> resident model.
>
> `GET /api/v1/health` lists what is currently loaded.

That last sentence is worth adding regardless: it is how the rest of the stack
does discovery and it is not mentioned anywhere in the skill.

### 2.2 HIGH — `route_trace` is under-sold and arrives too late

The `x-lemonade-route` header and the `"route_trace": true` body field are the
only way to tell a working policy from one that is silently falling back — which
is the exact failure the skill spends most of Step 4 warning about. Yet they
appear in a two-sentence paragraph *after* the curl block at the very end of
Step 8.

Right now the skill tells the user "here is a catastrophic silent failure mode"
and then buries the instrument that detects it.

**Suggested fix.** Promote it to its own Step 9, "Verify the policy actually
routes," with an explicit acceptance test:

```bash
# Send one prompt per rule (plus one that should hit no rule) and confirm
# matched_rule is what you expect — not `default` for everything.
curl -sS -X POST http://localhost:13305/api/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"<model_name>","route_trace":true,
       "messages":[{"role":"user","content":"<prompt targeting rule-N>"}]}' \
| python3 -c 'import json,sys; d=json.load(sys.stdin)["x_lemonade_route"]; print(d["matched_rule"], d["default_used"])'
```

> **If `default_used` is true for every prompt, the policy is not routing.** In
> Mode A this almost always means the judge's reply failed to parse — re-read
> the prompt rules in Step 4.

That connects the warning to its diagnostic, which is currently the missing link.

### 2.3 MEDIUM — The silent-fallback claim needs a stated basis **[unverified]**

Step 4 makes a strong, specific, falsifiable claim: imperative prompts cause
weaker judge models to reply with a bare string, which "causes … silently
falling back to `default_model` on every request with no visible error."

I believe it, and it is the most valuable thing in the skill. But it is stated
without a version, a model, or a measured rate. Two problems follow:

1. A reader cannot tell whether it applies to their judge model. "Weaker models"
   is not actionable — is a 4B judge weak? A 0.6B?
2. If a future parser gets more forgiving, nothing tells the reader the guidance
   is stale.

**Suggested fix.** Add a one-line provenance note — "observed with `<model>` on
Lemonade `<version>`" — and, if there is a measured fallback rate, cite it. I am
planning to measure this (§4, T2) and will contribute numbers.

### 2.4 MEDIUM — Version currency **[unverified]**

The skill requires "v10.1.0+". Live here is **11.5.2**. The prerequisites and
the parser-strictness claims in `reference.md` have presumably not been
re-checked against 11.x.

**Suggested fix.** Either state a tested-against version explicitly ("validated
against 10.1.0–11.5.x") or add a note that the offline validator tracks a
specific parser revision. A user on 11.5.2 currently has no way to know whether
"the strict server-side parser" description still holds. My T1 will produce a
concrete answer for 11.5.2.

### 2.5 MEDIUM — No guidance on composing with an external control plane

The skill implicitly assumes `collection.router` is the whole routing story. In
practice it is usually one layer among several — here it would sit under CCR and
alongside a registry-bound resolver.

Unanswered, and reasonable for a user to ask:

- Should content-based routing live in `collection.router` or in the caller?
- If a caller already picks a model, does a router policy override it?
- Is it sane to have a router policy as a *candidate* of another router policy?

**Suggested fix.** A short "Where this fits" section near the top — three or four
sentences distinguishing `collection.router` (content-aware, server-side,
per-request) from client-side routers (request-class-aware, no prompt
inspection). This also strengthens the skill's pitch: content-awareness is the
thing the other layers structurally cannot do.

### 2.6 LOW — Step 8's mandatory-pairing language fights the checklist

Step 8 opens with "These two actions are a single mandatory step. Do not stop
between them," then labels them 8a and 8b. If they truly cannot be separated,
they should not be numbered separately; if the concern is the agent halting
after validation, say that directly.

Minor, but this skill is otherwise unusually precise about instruction shape, so
it stands out.

### 2.7 LOW — `metadata` caveat is buried in a table cell

"not editable in the desktop UI yet — use only when the user asks for metadata
routing" is a meaningful constraint sitting in the last cell of the match-leaf
table. A user who picks `metadata` routing and then cannot see it in the Hybrid
Router editor will assume the policy is broken.

**Suggested fix.** Keep the table row, and add a sentence under the table listing
which match types round-trip through the desktop editor and which do not.

### 2.8 LOW — `min_score` semantics could use one example

`{"classifier": "clf-1", "label": "PII", "min_score": 0.5}` is described as a
"band test" with `min_score`/`max_score` in `[0,1]`. It is not stated whether
the bound is inclusive, nor what a sensible threshold looks like for the
`semantic_similarity` type specifically (cosine similarity scores cluster very
differently from a classifier's softmax output — 0.5 is a reasonable default for
one and quite aggressive for the other).

**Suggested fix.** One sentence in `reference.md` on typical score ranges per
classifier type.

---

## 3. Suggestions worth considering

Not defects — ideas that would raise the ceiling.

### 3.1 Ship a `--dry-run` route simulator

The validator proves the JSON parses. It cannot tell the author that `rule-3` is
unreachable because `rule-1` subsumes it — the single most likely *semantic*
error given first-match-wins plus substring matching.

A `python scripts/validate.py router.json --simulate prompts.txt` mode that
evaluates the deterministic leaves (`keywords_*`, `regex`, `min_chars`,
`max_chars`, `has_tools`, `has_images`) offline and prints which rule each prompt
would hit — skipping classifier leaves as "requires server" — would catch
shadowed rules before registration. Everything needed is already in the
validator.

### 3.2 Emit a starter prompt set alongside the policy

Step 8b asks for "a short `<test prompt>` that should hit the first rule." Going
one better — one prompt per rule plus one that should reach `default_model`,
written to `router-prompts.txt` — turns §2.2's verification step into a loop the
user can actually run, and pairs naturally with 3.1.

### 3.3 Warn on classifier-only policies with no deterministic fast path

A policy whose every rule depends on a `classifier` or `llm` leaf adds an
inference call to *every* request. That is a real cost that the current defaults
do not surface. A validator warning — "no rule can be decided without a model
call; consider a keyword or length fast path for the common case" — would be
cheap and useful.

### 3.4 Say something about the empty-candidate-set failure

"If the user names none, ask — never invent model names" is right. Consider also
covering the adjacent case: the user names a model that is not in the local
registry. `curl /api/v1/models/<id>` is already curl #1 in Step 8b, but nothing
says what to do when it 404s — pull it, substitute, or stop and ask.

---

## 4. Planned live testing

| # | Test | Effort | Settles |
|---|---|---|---|
| T1 | Run `scripts/validate.py` over shipped `examples.md` pairs + hand-authored policies; run `evals/evals.py`; register one validated policy against live 11.5.2 and compare offline verdict to live parser | ~30 min | §2.4 |
| T2 | Silent-fallback experiment: two Mode A policies differing only in prompt style (imperative vs. intent-only), N prompts each, `route_trace: true`, count `default_used` | ~2 hrs | §2.3 |
| T3 | Slot-contention characterisation: 3-candidate policy on a single-`llm`-slot host; measure load/evict behavior and switch latency | ~1 hr | §2.1 |
| T4 | `semantic_similarity` accuracy against a known-ground-truth corpus (UAP cross-era terminology drift: FBI → 1947-48 "flying disc/saucer"; DOW → modern "UAP" only) | ~1 hr | 3.3, §2.8 |

T2 is the highest-value item — it converts the skill's most distinctive claim
from assertion into measurement. I will report numbers either way.

---

## 5. Summary

Genuinely well built. The scope discipline, the offline validator gate, and
especially the prompt-authoring guidance derived from the engine's appended
contract put this above most config-generator skills — it teaches the reader
things the schema cannot.

The gap is that it treats the policy as a **document** rather than as something
that runs on a **host with finite resources**. Everything in §2.1 and §2.2 comes
from that: no slot model, and the verification instrument for its own headline
failure mode arriving last and under-emphasised. Both are additive fixes; none
requires restructuring.

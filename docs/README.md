# Design documentation (pre-implementation)

Status: **DESIGN ONLY. No product feature is implemented by these documents.**
Authoritative requirements: `AGENTS.md` and `docs/product-spec.md` (unchanged by this stage).

| Doc | Contents |
|---|---|
| [01-journey-and-navigation.md](01-journey-and-navigation.md) | User journeys, where invitation fits, screen/route map, returning to a plan, slots for later features |
| [02-layouts-and-states.md](02-layouts-and-states.md) | Desktop / Android app / Android mobile web layouts; empty, loading, error, populated states; unfinished destinations |
| [03-visual-system.md](03-visual-system.md) | Typography, color (with measured contrast), spacing, components, status indicators, touch targets |
| [04-data-and-security.md](04-data-and-security.md) | Data relationships, RLS, private storage, PDF preview/download, concurrency, time, localization |
| [05-space-connection.md](05-space-connection.md) | Connecting two one-member Spaces: disclosure, server rules, transaction, retry, files |
| [06-scope-acceptance-decisions.md](06-scope-acceptance-decisions.md) | Initial vs later scope, proposed stages, acceptance criteria, unresolved decisions |

## Input findings
* `AGENTS.md` and `docs/product-spec.md`: read in full. The spec **already contains** the agreed PDF behavior
  (section 7: in-app preview without prior download, separate original download/save, member-only private access),
  so it was **preserved unmodified**.
* "Available photo-input findings": **no such file was found** (resolved: owner chose defaults, 3 MB limit, copy & paste) (project files are only `AGENTS.md` and
  `product-spec.md`; no uploads). Nothing was invented. Photo handling below follows only the spec
  (photos are optional, private Space attachments on Activity Cards). Resolved: the owner chose the defaults, a 3 MB limit and copy & paste (doc 04 §6).

## Labels used
* **Requirement** = stated in AGENTS.md / spec.  **Proposed** = design recommendation awaiting confirmation.
* **Unresolved (U-nn)** = listed in doc 06; not decided here.
* **Decided** = chosen by the project owner; recorded in doc 06 §4 and `docs/product-spec.md` §12.

# Labs 360 Capture Names Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every published panorama a distinct hybrid place-and-mood title in French and English.

**Architecture:** Change `Labs360Place.name` from a scalar to localized `{ fr, en }` data, then resolve it once while producing SSR/runtime data in `Labs360.astro`. Keep client scripts language-agnostic by continuing to receive a plain localized string. Update automatic ingestion to emit bilingual name objects with the same geocoded name in both languages.

**Tech Stack:** Astro, TypeScript, browser JavaScript, Bash 3.2, Python 3, shell regression tests.

## Global Constraints

- Panorama titles use the approved `Lieu — évocation` convention.
- The two photo titles remain unchanged.
- French and English render their corresponding title.
- Viewer, cards, MapKit and structured data consume the active-language string.
- Future automatic imports remain valid without inventing a creative subtitle.
- Astro must still build exactly ten pages.

---

### Task 1: Localized capture data and SSR/runtime resolution

**Files:**
- Modify: `src/data/labs360.ts`
- Modify: `src/components/pages/Labs360.astro`
- Test: `tests/labs360-page.sh`

**Interfaces:**
- Produces: `Labs360Place.name: { fr: string; en: string }`
- Produces: localized `visiblePlaces` records whose `name` is a plain string for UI and client scripts.

- [ ] **Step 1: Write failing page-contract tests**

Add assertions that the six panorama IDs contain the exact approved French and
English names, that both photo names remain identical across languages, and
that `Labs360.astro` resolves `name: place.name[lang]`.

- [ ] **Step 2: Run the tests and verify the contract fails**

Run: `bash tests/labs360-page.sh`

Expected: failures for scalar names and the stale exact-six-place assumption.

- [ ] **Step 3: Implement localized data**

Change the interface to:

```ts
name: { fr: string; en: string };
```

Set the six approved bilingual panorama titles and wrap the two photo titles in
matching `fr` / `en` values.

- [ ] **Step 4: Resolve names at the server boundary**

Map `PLACES` into language-specific objects before structured data, meta tags,
cards and runtime JSON:

```ts
const visiblePlaces = PLACES
  .filter((place) => place.city === 'quebec' && Boolean(place.media))
  .map((place) => ({ ...place, name: place.name[lang] }));
```

- [ ] **Step 5: Run the page tests**

Run: `bash tests/labs360-page.sh`

Expected: all page tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/data/labs360.ts src/components/pages/Labs360.astro tests/labs360-page.sh
git commit -m "feat(labs360): name panoramas by place and perspective"
```

### Task 2: Keep automatic ingestion compatible

**Files:**
- Modify: `scripts/iso360-core.sh`
- Modify: `tests/labs360-pipeline.sh`

**Interfaces:**
- Consumes: geocoder field `g['name']`.
- Produces: TypeScript `name: { fr: string, en: string }` for new automatic entries.

- [ ] **Step 1: Write a failing pipeline assertion**

Update the wire-format test to require:

```ts
name: {
  fr: "Generated place",
  en: "Generated place",
},
```

- [ ] **Step 2: Run the pipeline tests and verify failure**

Run: `bash tests/labs360-pipeline.sh`

Expected: the core-wire test fails because it still emits a scalar name.

- [ ] **Step 3: Update `core_wire`**

Replace the scalar name line with a bilingual object using the same trusted
geocoded name for both languages. Do not generate an editorial subtitle.

- [ ] **Step 4: Run pipeline and page tests**

Run:

```bash
bash tests/labs360-pipeline.sh
bash tests/labs360-page.sh
```

Expected: both suites pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/iso360-core.sh tests/labs360-pipeline.sh
git commit -m "fix(labs360): keep ingestion compatible with localized names"
```

### Task 3: Production verification and deployment

**Files:**
- Verify only; no planned source changes.

**Interfaces:**
- Consumes: completed localized data and compatible ingestion.
- Produces: production pages with eight captures and six distinct panorama titles.

- [ ] **Step 1: Run the complete verification**

Run:

```bash
bash tests/labs360-page.sh
bash tests/labs360-pipeline.sh
npm run build
git diff --check origin/main...HEAD
```

Expected: all tests pass, Astro builds ten pages, and the diff is clean.

- [ ] **Step 2: Verify built FR/EN output**

Check `dist/labs/360/index.html` and `dist/en/labs/360/index.html` for all six
language-specific titles and exactly eight `data-place-id` controls.

- [ ] **Step 3: Push the isolated branch to production**

Run:

```bash
git push origin HEAD:main
```

- [ ] **Step 4: Verify Vercel and live HTML**

Wait for the GitHub/Vercel commit status to become `success`, then verify the
French and English production pages contain the expected localized titles.

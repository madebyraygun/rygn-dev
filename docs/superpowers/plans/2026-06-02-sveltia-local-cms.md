# Sveltia Local CMS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Sveltia CMS local editing UI at `/admin` for editing blog Posts with a WYSIWYG body, writing directly to the existing markdown files.

**Architecture:** Sveltia loads from CDN into two static files under `src/admin/`, passthrough-copied by Eleventy and served at `localhost:8080/admin/`. Its local backend (File System Access API) edits `src/posts/*.md` directly. To make WYSIWYG safe, the inline `seriesNav` shortcode is lifted out of post bodies into frontmatter, rendered by the post layout. The publish flow (`git commit` + `./deploy.sh`) is unchanged; `/admin` is excluded from the production rsync.

**Tech Stack:** Eleventy 3 (Liquid templates), Sveltia CMS (CDN), bash/rsync deploy.

---

## File Structure

- `src/_includes/post.html` (modify) — renders `seriesNav` from a frontmatter `series` field.
- `src/posts/why-we-host-craft-on-dokku.md`, `src/posts/dokku-craft-starter-guide.md`, `src/posts/remote-cli-makes-dokku-feel-local.md` (modify) — move series association from body shortcode to frontmatter.
- `src/admin/index.html` (create) — loads Sveltia from CDN.
- `src/admin/config.yml` (create) — CMS backend + Posts collection config.
- `eleventy.config.js` (modify) — passthrough-copy `src/admin`.
- `deploy.sh` (modify) — exclude `admin` from rsync.

There is no test framework in this project. Verification is by build output (`npm run build`) and `git diff` on `_site`, plus a manual browser check of `/admin`.

---

## Task 1: Lift seriesNav from post bodies into frontmatter

This is a behavior-preserving refactor. The rendered HTML must stay equivalent — the goal is pure-markdown bodies so the WYSIWYG editor (Task 3) can't mangle template code.

**Files:**
- Modify: `src/_includes/post.html`
- Modify: `src/posts/why-we-host-craft-on-dokku.md`
- Modify: `src/posts/dokku-craft-starter-guide.md`
- Modify: `src/posts/remote-cli-makes-dokku-feel-local.md`

- [ ] **Step 1: Capture current rendered output as the baseline**

Run:
```bash
cd /Users/dalton/Sites/raygun-dev/dev
npm run build
cp _site/posts/why-we-host-craft-on-dokku/index.html /tmp/p1-before.html
cp _site/posts/dokku-craft-starter-guide/index.html /tmp/p2-before.html
cp _site/posts/remote-cli-makes-dokku-feel-local/index.html /tmp/p3-before.html
grep -c 'class="series-nav"' /tmp/p1-before.html
```
Expected: build succeeds; the grep prints `1` (the series nav is present in the baseline).

- [ ] **Step 2: Update the post layout to render seriesNav from frontmatter**

In `src/_includes/post.html`, insert the conditional nav between the post-meta line and `{{ content }}`. The result must read:
```liquid
---
layout: base.html
---
<article class="post">
  <h1>{{ title }}</h1>
  <p class="post-meta">{{ date | postDate }} &middot; by {{ author }}</p>
  {% if seriesKey %}{% seriesNav seriesKey, page.url %}{% endif %}
  {{ content }}
```
Leave the rest of the file (the prev/next `post-nav` block and closing tags) unchanged.

**Note:** the frontmatter key is `seriesKey`, NOT `series`. `src/_data/series.json` registers a global Eleventy variable named `series` (the series-definition object) which would shadow a `series` frontmatter key and break the nav. `seriesKey` avoids the collision.

- [ ] **Step 3: Move the shortcode into frontmatter in all three posts**

For each of the three files, delete body line 6 (`{% seriesNav "craft-on-dokku", page.url %}`) and add `seriesKey: craft-on-dokku` as the last frontmatter key. After editing, the top of each file must read:
```markdown
---
title: "..."
date: ...
description: "..."
seriesKey: craft-on-dokku
---

<first body paragraph>
```
Keep each file's existing `title`/`date`/`description` values exactly as they are. Ensure exactly one blank line between the closing `---` and the first paragraph (the line that previously held the shortcode is removed).

Verify no shortcode remains in any body:
```bash
grep -rn "seriesNav" src/posts
```
Expected: no output.

- [ ] **Step 4: Rebuild and diff against the baseline**

Run:
```bash
npm run build
diff /tmp/p1-before.html _site/posts/why-we-host-craft-on-dokku/index.html
diff /tmp/p2-before.html _site/posts/dokku-craft-starter-guide/index.html
diff /tmp/p3-before.html _site/posts/remote-cli-makes-dokku-feel-local/index.html
grep -c 'class="series-nav"' _site/posts/why-we-host-craft-on-dokku/index.html
```
Expected: each `diff` shows **no differences** (the nav previously sat at the very top of the body and now renders in the same position via the layout, so output is identical). The grep prints `1`. If a diff shows only insignificant whitespace around the nav block and the `series-nav` markup is byte-identical, that is acceptable; any change to the nav markup or content is a failure — stop and fix.

- [ ] **Step 5: Commit**

```bash
git add src/_includes/post.html src/posts/why-we-host-craft-on-dokku.md src/posts/dokku-craft-starter-guide.md src/posts/remote-cli-makes-dokku-feel-local.md
git commit -m "Render series nav from frontmatter instead of body shortcode"
```

---

## Task 2: Add the Sveltia admin files and serve them

**Files:**
- Create: `src/admin/index.html`
- Create: `src/admin/config.yml`
- Modify: `eleventy.config.js`

- [ ] **Step 1: Create `src/admin/index.html`**

```html
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Content Manager</title>
    <link href="config.yml" type="application/yaml" rel="cms-config-url" />
  </head>
  <body>
    <script src="https://unpkg.com/@sveltia/cms/dist/sveltia-cms.js"></script>
  </body>
</html>
```

- [ ] **Step 2: Create `src/admin/config.yml`**

```yaml
backend:
  name: github
  repo: madebyraygun/rygn-dev
  branch: main
local_backend: true

media_folder: src/static
public_folder: /static

collections:
  - name: posts
    label: Posts
    folder: src/posts
    create: true
    slug: "{{slug}}"
    extension: md
    format: frontmatter
    fields:
      - { name: title, widget: string }
      - { name: date, widget: datetime, format: "YYYY-MM-DD", time_format: false }
      - { name: description, widget: text }
      - name: seriesKey
        label: Series
        widget: select
        required: false
        options:
          - { label: "Hosting Craft CMS on a Bare VPS", value: "craft-on-dokku" }
      - { name: body, widget: markdown, modes: [rich_text, raw] }
```

- [ ] **Step 3: Passthrough-copy the admin folder in Eleventy**

In `eleventy.config.js`, directly below the existing `eleventyConfig.addPassthroughCopy("src/static");` line, add:
```js
  eleventyConfig.addPassthroughCopy("src/admin");
```

- [ ] **Step 4: Build and confirm the admin files are emitted**

Run:
```bash
npm run build
test -f _site/admin/index.html && test -f _site/admin/config.yml && echo "admin OK"
```
Expected: prints `admin OK`.

- [ ] **Step 5: Manual browser check of the CMS**

Run `npm run dev`, then in a Chromium browser (Chrome/Edge/Arc) open `http://localhost:8080/admin/`. Choose the local-repository / "work with local repository" option and grant access to the project folder when prompted.
Expected:
- The Posts collection lists the 3 existing posts.
- Opening a post shows populated `title`, `date`, `description`, and `Series` = "Hosting Craft CMS on a Bare VPS", with the body rendered in the rich-text (WYSIWYG) editor and a raw-mode toggle available.
Stop the dev server when done (Ctrl-C).

- [ ] **Step 6: Round-trip check — edit and save does not corrupt a file**

In the CMS, open `why-we-host-craft-on-dokku`, make a trivial body edit in rich-text mode, save, then revert the edit and save again. Run:
```bash
git diff src/posts/why-we-host-craft-on-dokku.md
```
Expected: no diff (the file round-trips cleanly through the editor). If frontmatter key order or body markdown changed materially, note it; minor frontmatter reordering by the CMS is acceptable as long as `title`/`date`/`description`/`seriesKey` values are intact and the body markdown is unchanged.

- [ ] **Step 7: Commit**

```bash
git add src/admin/index.html src/admin/config.yml eleventy.config.js
git commit -m "Add Sveltia local CMS at /admin for editing posts"
```

---

## Task 3: Exclude /admin from the production deploy

**Files:**
- Modify: `deploy.sh`

- [ ] **Step 1: Add an exclude for `admin` to the rsync invocation**

In `deploy.sh`, the rsync command currently reads:
```bash
rsync -avz --delete ${dry:+"$dry"} \
  -e "ssh -p ${SSH_PORT}" \
  --exclude '.DS_Store' \
  _site/ "${HOST}:${REMOTE_PATH%/}/"
```
Add an `--exclude 'admin'` line directly below the `.DS_Store` exclude so it reads:
```bash
rsync -avz --delete ${dry:+"$dry"} \
  -e "ssh -p ${SSH_PORT}" \
  --exclude '.DS_Store' \
  --exclude 'admin' \
  _site/ "${HOST}:${REMOTE_PATH%/}/"
```

- [ ] **Step 2: Verify the dry-run does not transfer admin**

Run:
```bash
npm run build
./deploy.sh --dry-run 2>/dev/null | grep -c '^admin/' || true
```
Expected: prints `0` (no `admin/` paths in the transfer list). Note: this step contacts the remote host over SSH; if the host is unreachable, instead confirm by inspection that `--exclude 'admin'` is present in `deploy.sh` and that `--delete` plus the exclude will skip the directory.

- [ ] **Step 3: Commit**

```bash
git add deploy.sh
git commit -m "Exclude /admin from production deploy"
```

---

## Verification (whole feature)

- `npm run build` succeeds; `_site/admin/index.html` and `_site/admin/config.yml` exist.
- `grep -rn "seriesNav" src/posts` returns nothing; the 3 posts carry `seriesKey: craft-on-dokku` in frontmatter.
- Rendered post HTML is unchanged versus the Task 1 baseline (series nav present, in the same position).
- `/admin` opens in a Chromium browser, lists Posts, edits with a WYSIWYG body, and writes clean markdown on save.
- `./deploy.sh --dry-run` does not list any `admin/` paths.

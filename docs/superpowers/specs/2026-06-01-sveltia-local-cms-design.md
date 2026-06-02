# Sveltia local editing UI for Posts

## Goal

Add a nicer local editing UI for blog posts using Sveltia CMS, served at
`/admin` during local development. The CMS edits the existing markdown files on
disk; the publish workflow (`git commit` + `./deploy.sh`) is unchanged. Scope is
**Posts only** — series landing pages and `src/_data/series.json` stay
hand-edited.

## Why local-only

The site deploys via rsync to a custom server (not Netlify/GitHub Pages), so a
hosted Git-backed editor would commit content that still wouldn't go live until a
manual rebuild + rsync. The user wants a better authoring UI on their own
machine, not remote/multi-device editing. Sveltia's **local backend** uses the
browser File System Access API to read/write files directly — no OAuth, no proxy
server, no network round-trip.

## Architecture

- Sveltia is a single JS bundle loaded from CDN into two static files under
  `src/admin/`.
- `eleventy.config.js` passthrough-copies `src/admin`, so the editor is served at
  `http://localhost:8080/admin/` by `npm run dev`.
- The local backend writes directly to `src/posts/*.md` on disk. Editing flow:
  edit in browser → save → file written → `git commit` + `./deploy.sh` as today.
- **Browser requirement:** a Chromium-based browser (Chrome, Edge, Arc). Firefox
  and Safari lack the File System Access API the local backend needs.

## WYSIWYG enablement (architectural change)

The only template code in any post body is the inline
`{% seriesNav "craft-on-dokku", page.url %}` shortcode, present in 3 posts (all
the same series). A rich-text editor would try to interpret/escape it. Rather
than fall back to raw-only editing, lift series association into frontmatter so
bodies become pure markdown and WYSIWYG round-trips cleanly.

- **`src/_includes/post.html`** — render the nav from frontmatter. Between the
  `post-meta` line and `{{ content }}`, add:
  ```liquid
  {% if seriesKey %}{% seriesNav seriesKey, page.url %}{% endif %}
  ```
  The frontmatter key is `seriesKey`, not `series`: `src/_data/series.json`
  registers a global Eleventy variable named `series` (the series-definition
  object) that would shadow a `series` frontmatter key and suppress the nav.
- **The 3 craft-on-dokku posts**
  (`why-we-host-craft-on-dokku.md`, `dokku-craft-starter-guide.md`,
  `remote-cli-makes-dokku-feel-local.md`) — delete the inline `seriesNav` line
  from the body and add `seriesKey: craft-on-dokku` to the frontmatter.
- The existing `seriesNav` shortcode already takes a key + `page.url` and works
  the same whether the key is a literal or a variable. Generated HTML is
  unchanged.

Angle-bracket text such as `remote <env> <verb>` and `<password>` lives inside
code fences/backticks and is preserved verbatim by the markdown editor — no
action needed.

## Files

### New: `src/admin/index.html`
Minimal page linking the config and loading the CMS bundle from CDN:
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

### New: `src/admin/config.yml`
```yaml
backend:
  name: github
  repo: madebyraygun/rygn-dev
  branch: main
local_backend: true          # File System Access API on localhost

media_folder: src/static     # future image embeds land in /static
public_folder: /static

collections:
  - name: posts
    label: Posts
    folder: src/posts
    create: true
    slug: "{{slug}}"          # filename → /posts/<slug>/ via Eleventy
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

### Changed: `eleventy.config.js`
Add alongside the existing passthrough copy:
```js
eleventyConfig.addPassthroughCopy("src/admin");
```

### Changed: `src/_includes/post.html`
Insert the conditional `seriesNav` render between the post-meta line and
`{{ content }}` (see above).

### Changed: `deploy.sh`
Add `--exclude 'admin'` to the rsync invocation so the editor never ships to
production. The local backend can't edit live-server files anyway, but this keeps
`/admin` off prod.

## Field-design notes

- `author`, `layout`, `tags` are intentionally **not** CMS fields — they come
  from `src/posts/posts.json` directory defaults at build time. New posts stay
  clean and match existing files.
- The `seriesKey` select is hardcoded because series are rare. Adding a future
  series means adding one `options` line. (It is not modeled as a `relation`
  against `series.json` — that data file is out of scope and interdependent with
  the nav.)
- `seriesKey` is optional; an empty value renders no nav (`{% if seriesKey %}`
  treats empty as falsy).

## Verification

- `npm run dev`, open `http://localhost:8080/admin/` in Chrome, choose "work with
  local repository" / grant folder access, confirm the 3 existing posts list and
  open with populated fields including the correct `seriesKey` value.
- Edit a post body in rich-text mode, save, confirm the on-disk markdown is
  clean and the rendered post is unchanged (`npm run build`, diff `_site`).
- Create a new test post, confirm filename/slug and frontmatter shape match
  existing posts, then delete it.
- `./deploy.sh --dry-run` shows `admin/` is not transferred.

## Out of scope

- Series landing pages (`src/series/*.md`) and `src/_data/series.json` editing.
- Any hosted/remote editing, OAuth backend, or automated publish pipeline.
- Image/media management beyond setting `media_folder` for future use.

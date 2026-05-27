---
title: "remote: A Thin CLI That Makes Dokku and Craft CMS Feel Local"
date: 2026-05-27
description: "In the first post I made the case for hosting Craft CMS on Dokku and a bare VPS. I also admitted the one real cost: every routine operation is a verbose SSH incantation, one fat-fingered word away from running something destructive against production. This post is the fix."
---
{% seriesNav "craft-on-dokku", page.url %}

In [the first post in this series](/posts/why-we-host-craft-on-dokku/) I made the case for hosting Craft CMS on Dokku and a bare VPS: PaaS deploy ergonomics, full ownership of the box, and staging environments that are essentially free. I also admitted the one real cost. Every routine operation is a verbose SSH incantation, and the production command differs from the staging command by a single word. The day you fat-finger that word, you've run something destructive against the wrong environment.

That friction is exactly the tax managed hosting charges you to avoid. But it's a tooling problem, not an infrastructure problem, and tooling problems are the cheap kind to solve. This post is about the fix: a small CLI we built called `remote` that turns every one of those incantations into `remote <env> <verb>`, with production guardrails baked in.

It's a few hundred lines of Bash. It isn't clever the way a framework is clever. It just composes the tools we already trust into a shape that's hard to misuse, and along the way it unlocks a couple of workflows that raw SSH can't do at all.

## The friction, briefly

Post 1 covered the why, so I'll keep this short. Before `remote`, working against our environments looked like this:

```
ssh example.com "dokku run mysite php craft resave/entries --section=news"
```

Pulling the production database down to debug against real data meant a manual dump, download, and restore. Deploying was a `git push` to a remote with the right SSH key set through an environment variable you had to remember. None of it was hard, exactly. It was just repetitive, easy to get subtly wrong, and occasionally dangerous.

Two Craft-flavored sharp edges show up over and over in what follows, so they're worth naming now. The first is PHP's opcache, which happily serves stale bytecode after you change a file. The second is the production-versus-staging problem, where the only thing standing between a safe command and a destructive one is your attention at the moment you hit enter.

`remote` replaced a retired zsh alias called `dokku-craft` and a pile of ad-hoc `rclone` and database scripts.

## Design: environment first, everything else pluggable

The whole tool is organized around one idea. The environment is the first argument, not something baked into muscle memory.

```
remote <env> <command> [args...]
```

Every environment is a record in a config file, defined declaratively:

```bash
env_define mysite \
  ssh_host=example.com \
  dokku_remote=dokku \
  dokku_app=mysite \
  rclone_remote=mysite-production \
  ssh_key="$HOME/.ssh/id_ed25519_dokku" \
  local_dir="$HOME/Sites/mysite" \
  is_prod=1
```

Adding an environment is data, not code. The `is_prod=1` flag is the one to watch, and we'll come back to it.

The dispatcher itself is tiny. It sources a few library files (the environment registry, an SSH and rclone config reader, the confirmation prompts), loads the requested environment, and then sources a command file named after the verb. Each command file does exactly one thing: define a function called `remote_cmd_run`. Adding a verb means adding a file. There's no central switch statement to edit and no registration step.

The point of all this is restraint. `remote` doesn't reimplement anything. It shells out to `ssh`, `docker`, `tar`, `gzip`, `ddev`, and `gh`. The value isn't in the tools, it's in composing them correctly and safely every single time, so I don't have to.

## A tour of the verbs

Most of the surface area is the boring, useful stuff. Running things:

```
remote mysite craft resave/entries --section=news
remote mysite-staging craft clear-caches/all
remote mysite run "ls -la storage/runtime"
remote mysite shell
remote mysite logs -t
```

`craft` runs a Craft console command in the app container. `run` runs an arbitrary command. `shell` drops you into an interactive shell. `logs` tails the app. There's a small quality-of-life touch in here: Dokku emits some `/tmp/bashenv` noise on certain hosts, and `remote` filters it out so the output is just what you asked for.

Deploying:

```
remote mysite deploy dev
```

That runs the full `git push` release with the right SSH key wired in for you, so you never think about `GIT_SSH_COMMAND` again.

And configuration:

```
remote mysite config
remote mysite config get CRAFT_ENVIRONMENT
remote mysite config set --no-restart FOO=bar
```

These read and write Dokku's app config vars. The `--no-restart` flag matters more than it looks. When you're setting a variable the deployed code doesn't read yet, you don't want to trigger a pointless production restart to apply it.

## The clever bits

The verbs above are convenience. These next few are the reason the tool earns its keep, because they do things that are genuinely awkward or impossible to do reliably by hand.

### Hot-patching a running container

Sometimes you have a one-line CSS fix and a full Dokku rebuild feels absurd. `cp` streams local files straight into the running container:

```
remote mysite cp web/dist
```

Under the hood it's a single pipe:

```bash
tar czf - -C "$LOCAL_DIR" "${rel_paths[@]}" \
  | ssh "$SSH_HOST" "docker exec -i ${DOKKU_APP}.web.1 tar xzf - -C /app/"
```

It tars the paths you name, pipes the archive over SSH, and untars it inside the running web container. Files land at the same relative path under `/app/`. It's ideal for shipping built assets after an `npm run build` without a release. The one caveat to keep in mind: a hot patch lives in the running container only, so it survives until the next full deploy or restart, both of which rebuild from the registry image.

### Shipping a whole PR's diff

`cp` is the primitive. `deploy-pr` is the workflow built on top of it, and it's the one I reach for most:

```
remote mysite-staging deploy-pr 1862
remote mysite deploy-pr            # current branch's diff vs origin/HEAD
```

Given a PR number, it pulls the changed file list from `gh pr diff`. Given nothing, it diffs the current branch against its base. Then it does the thinking I'd otherwise do in my head:

- It filters out tests, docs, scratchpads, and any files the diff deleted, since you can't tar a file that no longer exists.
- If the diff touched JavaScript or SCSS, it knows the built assets are now stale, so it offers to run `ddev npm run build` and adds `web/dist` to the payload.
- Then it hands everything to `cp` with an opcache reset on the end.

One command takes a PR from "merged" to "running on staging" without a full rebuild cycle. For front-end iteration on a Craft site, that loop is the difference between testing something in seconds and testing it in minutes.

### Resetting opcache without undoing your work

This is the one I'm fondest of, because it's a genuinely tricky problem hiding behind a plain-looking command.

PHP's opcache caches compiled bytecode. When you hot-patch a PHP file into a running container, opcache keeps serving the old version, so your change appears to do nothing. The obvious fix is to restart the container, but `dokku ps:restart` triggers a full release-and-replace from the registry image, which wipes out the very files you just hot-patched. The cure undoes the patient.

So `opcache-reset` takes a different route. It writes a tiny PHP file with a random token in its name into the running container's webroot, curls it once to trigger `opcache_reset()`, and then deletes the file through an exit trap so cleanup happens even if something fails partway:

```php
<?php opcache_reset(); echo 1;
```

Opcache is shared across every PHP-FPM worker in the pool, so a single request clears it for all of them. You end up with a clean opcache and your hot-patched files still in place. This is why `cp --reset-opcache` and `deploy-pr` can hand-patch code and have it actually take effect.

### Worktree-aware database pulls

`db pull` refreshes the local database from a remote environment. It streams `dokku mysql:export` over SSH, gzips it locally to save bandwidth, and restores it through `ddev import-db`.

The detail I like is that it figures out where "local" actually is. We use git worktrees heavily, so the database you want to refresh isn't always the canonical project directory. Before writing anything, `db pull` checks whether you're sitting in a different worktree of the same repo and, if so, restores into that one instead. Running the command from wherever you happen to be working does the right thing.

### Syncing one environment from another, safely

`db sync-from` copies one environment's database into another, entirely on the shared Dokku host, with no round-trip to your laptop:

```
remote mysite-staging db sync-from mysite
```

Because this overwrites a database, it earns a couple of safety rails. It takes a pre-sync backup of the target first and tells you where it lives, so a mistake is recoverable. And after the import it runs `project-config/apply` on the target, which is the Craft-specific step that's easy to forget and confusing to debug when you do.

## Guardrails on production

Every destructive verb routes through one function, and that function reads the `is_prod` flag from the environment record. Deploys, database pushes, config changes, and hot-patches against a production environment all stop and ask first:

```
⚠️  Hot-patch files into container on PRODUCTION environment 'mysite'.
Continue? (y/n)
```

There's a small refinement that keeps this from becoming annoying. Some operations are compound. `cp --reset-opcache` internally calls the `opcache-reset` verb, which would normally prompt on its own. Once you've confirmed for a given invocation, `remote` remembers it and won't ask twice for the same run. One decision, not a gauntlet of them.

The other quiet guardrail is correctness under failure. The database commands stream through pipes, and a naive pipe will happily report success even if the SSH side died, because `gzip` exits cleanly on whatever it received. `remote` sets `pipefail` so a failed export surfaces as a failure instead of leaving you with a truncated dump you don't discover until you try to restore it.

## What I'd tell you if you built your own

A few things held up well enough that I'd repeat them.

A declarative environment registry beats a pile of shell aliases the moment you have more than one environment. Adding a server is filling in a record, and every command works against it for free.

Encode danger as data. The difference between a safe command and a destructive one shouldn't live in your attention. Marking an environment `is_prod=1` and routing every risky verb through one confirmation turns "be careful" into something the tool enforces.

Compose, don't reimplement. The whole thing is a thin layer over `ssh`, `docker`, `tar`, and friends. That's a feature. There's almost nothing to maintain, and when something breaks I'm debugging a one-line pipe, not a framework.

And some capabilities only exist once you wrap them. Hot-patching plus an opcache reset is too fiddly and too error-prone to do by hand every time, so without a wrapper you simply wouldn't. The tool doesn't just make the work faster, it makes a workflow available that otherwise wasn't.

To be honest about the limits, only our Dokku-hosted environments are wired into `remote` today. A few older non-Dokku hosts still use the interactive scripts they always did, and that's fine. The tool earns its place on the environments we touch every day.

## Wrapping up

`remote` gives every environment the same mental model. Logs, deploys, database operations, config, and hot patches all look like `remote <env> <verb>`, the dangerous ones stop and ask, and a couple of Craft-specific workflows that used to be genuinely annoying are now one command.

Back in the first post I framed the operational friction as the one real cost of self-hosting Craft on Dokku. This is how we paid it off. The platform choice was already a good one. The tooling is what makes living with it a pleasure.

If you want to build something similar, the shape is straightforward enough to lift: a declarative environment registry, a dispatcher that sources one file per verb, and a single confirmation gate keyed on an `is_prod` flag. I'll put a sanitized skeleton up so you have a starting point.

---

*This is the third and final post in a series on hosting Craft CMS the way we actually do it. It follows [the case for Dokku on a bare VPS](/posts/why-we-host-craft-on-dokku/) and [the hands-on starter guide](/posts/dokku-craft-starter-guide/).*

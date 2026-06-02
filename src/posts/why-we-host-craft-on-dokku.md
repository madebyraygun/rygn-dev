---
title: "Why We Host Craft CMS on Dokku and a $20 VPS"
date: 2026-05-20
description: "Every Craft CMS project eventually forces the same decision: where does this thing actually live? It's an easy question to put off during a build and a painful one to get wrong at launch."
seriesKey: craft-on-dokku
---

Every Craft CMS project eventually forces the same decision: where does this thing actually live? It's an easy question to put off during a build and a painful one to get wrong at launch. The usual answers all involve a trade you might not notice you're making, whether that's money, control, or the slow tax of doing everything by hand.

We host most of our production Craft sites on Dokku running on a single bare VPS. Almost nobody recommends this out loud, and after a few years of running real client sites on it, I've come to think that's a mistake. For a small team it hits a sweet spot the popular options miss: the deploy experience of a platform-as-a-service, on hardware you fully own, for a fraction of what managed hosting costs.

I want to be honest up front, because this isn't a "free hosting" pitch. It's a deliberate trade. You swap part of your monthly bill for a modest, well-bounded amount of ownership. My argument is that the trade is a good one, and that the part everybody dreads, being your own sysadmin, is smaller and more contained than it sounds.

## The Craft hosting landscape, and why each option chafes

There are four roads most teams go down.

**Managed Craft hosts** like Servd, Hyperlane, and Arcustech are genuinely excellent. They understand Craft, the developer experience is smooth, and someone else owns the pager. The catch is the pricing model. You pay per site, and often per environment. A staging server is another line item. Run a handful of small client sites, each wanting a staging copy, and the bill grows right alongside your portfolio. You're also boxed into their console the moment you need to do something unusual.

**A control panel plus a VPS**, like Laravel Forge or Ploi, is cheaper and gives you the box. But you're still hand-assembling Nginx and PHP-FPM configs for each site, and your deploys are bespoke shell scripts you maintain forever. It's a toolkit, not a platform.

**Generic PaaS**, the Heroku-likes, have lovely deploys, but PHP is rarely a first-class citizen, and once you add a database and a Redis instance the add-on pricing climbs fast.

**Raw server administration** is maximum control and maximum toil. You own every config file and every security update, with no abstraction doing the boring parts for you.

The gap in the middle is obvious once you see it. You want PaaS deploy ergonomics, but self-hosted, multi-app, and without per-environment pricing. That's the Dokku-shaped hole.

## What Dokku actually is

Dokku is, more or less, self-hosted Heroku built out of a pile of Bash and Docker. You install it on one Linux box and it hands you a small, sharp set of PaaS primitives:

- **Apps**, each isolated in its own container.
- **Git-push deploys.** `git push dokku main` builds an image and releases it.
- **Buildpacks or a Dockerfile.** Bring your own build, or let a buildpack detect PHP and do it for you.
- **Plugins and add-ons.** MySQL, Redis, and Let's Encrypt are one command each.
- **Zero-downtime deploys** via health checks and a rolling release.
- **Config vars**, managed per app.

The mental model is the part that matters. You `git push`, Dokku builds an image, runs your release steps, and swaps the new container in behind the proxy. One box can host many apps, each in its own container, each with its own linked database. There's no proprietary control plane and no vendor who can change your pricing tier or sunset the product out from under you. Dokku is mature, widely deployed, and in the best possible sense, boring.

That boringness is a feature. The thing hosting your clients' sites should be the least exciting technology in your stack.

## Why Dokku fits Craft specifically

General-purpose praise is cheap. The real question is whether Dokku maps cleanly onto what a Craft application actually needs, and it does, almost suspiciously well, because Craft is a fairly conventional PHP app with predictable infrastructure requirements.

**PHP-FPM and a web server.** Handled by the PHP buildpack or a small Dockerfile. Craft's `web/` directory maps straight to the container's webroot, with nothing exotic to configure.

**MySQL.** `dokku mysql:create mysite-db` provisions a managed MySQL service, and `dokku mysql:link mysite-db mysite` injects the connection string into the app as a config var. Craft reads it from the environment and connects. The database lives in its own container with its own data volume, independent of app deploys.

**Redis for cache, sessions, and the queue.** Same story. `dokku redis:create`, then link it. Point Craft's cache and queue components at the injected Redis URL and you've moved all the ephemeral state out of the app container, so deploys don't blow away sessions or cached data.

**Persistent asset storage.** User-uploaded files have to survive a deploy, and deploys replace the whole container. Either mount a Dokku persistent storage directory for Craft's volumes, or, better for most sites, offload volumes to S3-compatible object storage like Cloudflare R2. Both are a clean fit.

**The queue, scheduled tasks, and migrations.** This is where a locked-down managed console often gets in your way and Dokku doesn't. You declare your processes in a `Procfile`:

```
# Procfile
web:     heroku-php-nginx -C conf/nginx.conf web/
worker:  php craft queue/listen --verbose
release: php craft up --interactive=0
```

Three things worth pointing out here. The `web` process serves the app through nginx, with a small custom config to handle Craft's front-controller routing (the [starter guide](/posts/dokku-craft-starter-guide/) covers that config). The `worker` process is a dedicated queue runner, because Craft's queue wants a real worker in production rather than one piggybacking on web requests; run `dokku ps:scale mysite worker=1` and it's going. And the `release` process runs on every deploy, after the image is built but before the new container takes traffic, which is exactly where database migrations and project-config changes belong.

For anything on a clock, like Craft's garbage collection, Dokku reads a `cron` array from `app.json`:

```json
{
  "cron": [
    { "command": "php craft gc", "schedule": "@daily" }
  ]
}
```

**Project config.** Craft's project-config workflow and git-push deploys are made for each other. Your `project.yaml` travels with the code, and `php craft up` in the release step applies it on every deploy, in the right order, before the new container goes live. The config that describes your site ships with the commit that depends on it.

**Full console access.** Because you own the box, every `php craft` command is available over SSH, whether that's `resave/entries`, your own module commands, or a one-off maintenance script. No managed console decides which commands you're allowed to run.

**Multi-app on one box.** Production and staging are simply two Dokku apps, `mysite` and `mysite-staging`, sharing a host and, if you like, nothing else. Staging stops being a billing decision and becomes essentially free. Spinning up a throwaway environment to test a gnarly migration is one `dokku apps:create` away.

## The economics

Here's the part that makes the spreadsheet sing. A single capable VPS, a few shared vCPUs and several gigs of RAM from Hetzner or DigitalOcean, runs somewhere in the $20 to $40 per month range. That one box comfortably hosts several small-to-mid Craft sites plus their staging apps, their databases, and their Redis instances.

Now price the same portfolio on a managed Craft host. Each production site is its own plan, each staging environment is another charge, and the total grows right alongside how many sites you run. For an agency with a stable of client sites, the difference isn't a rounding error. It's the kind of recurring margin that changes which projects are worth taking.

To be fair to the managed hosts, you're not comparing identical things. Their price bundles automated backups, monitoring, and human support. With Dokku you buy those back with your own time and tooling, which is exactly the trade-off worth being honest about.

## Control you don't get anywhere else

Cost is the headline, but the capability is what keeps us here.

You have full SSH and a shell into any container. You can run anything Craft or Composer offers, on demand, against any environment. You can take a database dump, sync staging from production, or do careful surgery on a table without filing a support ticket. You can run arbitrary supporting services, a queue dashboard, a scheduled report, a sidecar process, as just more Dokku apps, without asking anyone's permission.

You can even hot-patch a running container: push a CSS fix into the live app without waiting on a full rebuild-and-release cycle. That's possible only because you own the box, and it's the kind of thing that turns a 15-minute deploy into a 5-second one when you need it. More on how we made that pleasant in the next post.

And there's no lock-in. Underneath the abstraction it's just Docker, MySQL, and git. Moving off Dokku, to another host, another VPS, eventually to Kubernetes if you outgrow a single box, is a `docker` image and a `mysqldump` away, not a re-platforming project.

## The honest trade-offs

I'd be doing you a disservice if I pretended this was free. Self-hosting moves real responsibilities onto your plate, and you should walk in with your eyes open.

**You're the sysadmin now.** OS security updates, Docker upgrades, the occasional Dokku upgrade, all yours. In practice it's modest, an hour here and there, mostly `apt upgrade` and the rare Dokku point release, but it's nonzero and it never fully goes away.

**Backups are your job.** Nobody is silently snapshotting your database. You have to set up automated dumps and, more importantly, get them off the box to separate storage. Our pattern is a scheduled task that streams a fresh production database dump to object storage every morning, so a bad day means a restore instead of a catastrophe. It works well, but you have to build it, and you have to actually test that restores work.

**One box is one blast radius.** A single VPS is a single point of failure. The mitigations are real (a managed-database option, regular snapshots, an image you can redeploy onto a fresh VPS in minutes), but if your site genuinely can't tolerate an hour of downtime, a single-box architecture is the wrong starting point.

**No managed support.** When something breaks at 11pm, you own the pager. There's no host to escalate to.

**There's a scaling ceiling.** Vertical scaling on one box goes further than most people expect, but it has a limit. Multi-node Dokku is possible, though that's the seam where its simplicity ends, and the point where I'd seriously weigh Kubernetes or a managed platform instead.

So who is this right for? Small teams and agencies running client sites with predictable traffic, comfortable in a terminal, who value cost and control. Who is it wrong for? No-ops teams, projects with hard compliance or high-availability requirements, and anything facing spiky web-scale traffic.

## The one downside worth its own post

If you net out those trade-offs, most are either small, like patching, or solvable with a bit of upfront engineering, like backups and redeploy-from-image. But there's one that grates every single day, and it's worth naming precisely, because it's what this series is really about.

Even with Dokku's lovely git-push deploys, the routine operations are still raw SSH incantations. Running a console command against production looks like this:

```
ssh example.com "dokku run mysite php craft resave/entries --section=news"
```

Pulling the database down to work against real data is a manual dump, download, restore dance. And every one of these commands differs from its staging equivalent by a single word, which means the day you fat-finger `mysite` where you meant `mysite-staging`, you've run a destructive operation against production.

That friction is, not coincidentally, exactly the tax managed hosting charges you to avoid. The good news is that it's a tooling problem, not an infrastructure problem, and tooling problems are the cheap kind to solve.

In [a later post in this series](/posts/remote-cli-makes-dokku-feel-local/) I'll walk through `remote`, the small CLI we built that collapses every one of those incantations into a single, safe shape:

```
remote mysite craft resave/entries --section=news
```

It bakes in production guardrails, so the fat-finger-into-prod failure mode simply can't happen.

## Wrapping up

Dokku on a bare VPS sits in a spot the popular options leave empty: PaaS deploy ergonomics, full ownership of the box, multi-app economics, and no per-environment pricing, in exchange for owning a bounded, manageable amount of operations work. For a small team running real Craft sites, that's less a compromise than a genuinely good deal.

It's a deliberate trade, not a free lunch. But it's the trade I'd make again, and have, across a whole portfolio of sites.

If you want to actually stand one of these up, the next piece in this series is a hands-on [Dokku-for-Craft starter guide](/posts/dokku-craft-starter-guide/), taking you from a fresh VPS to a deployed Craft app with MySQL, Redis, TLS, and a queue worker. After that, the [`remote` CLI](/posts/remote-cli-makes-dokku-feel-local/) that makes living with it a pleasure.

---

*This is the first post in a series on hosting Craft CMS the way we actually do it. Next: [the starter guide](/posts/dokku-craft-starter-guide/), then [the `remote` CLI](/posts/remote-cli-makes-dokku-feel-local/).*

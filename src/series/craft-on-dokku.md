---
layout: base.html
title: "Hosting Craft CMS on a Bare VPS: A Series"
permalink: /series/craft-on-dokku/
---
# Hosting Craft CMS on a Bare VPS: A Series

Most advice about where to host Craft CMS points you at a managed platform, hands you a monthly bill that grows with every site and every staging copy, and moves on. We took a different route. For years now we've run our production Craft sites on Dokku on plain, inexpensive VPS boxes we own outright, and it's been one of the better infrastructure decisions we've made.

This series is the whole story, in three parts: why we made that choice, how to set it up yourself, and how we made it pleasant to live with day to day. It's written for small teams and agencies who run real Craft sites, are comfortable in a terminal, and would rather own their hosting than rent it. If that's you, start at the top and read straight through.

## Part 1: The case for it

**[Why We Host Craft CMS on Dokku and a $20 VPS](/posts/why-we-host-craft-on-dokku/)**

The argument. Dokku gives you the deploy experience of a platform-as-a-service, on hardware you fully own, with no per-environment pricing, in exchange for a modest and well-bounded amount of operations work. This post walks the hosting landscape, explains why Dokku maps so cleanly onto what a Craft app actually needs, runs the economics, and is honest about the trade-offs you're signing up for. Read this to decide whether the approach is right for you.

## Part 2: The setup

**[A Dokku-for-Craft Starter Guide: From a Fresh VPS to a Deployed Site](/posts/dokku-craft-starter-guide/)**

The hands-on part. Nine steps from a bare Ubuntu box to a deployed Craft site with MySQL, Redis, automatic TLS, a real queue worker, and a staging environment alongside it. Every command is here, including the one genuine integration wrinkle (teaching Craft to read the database URL Dokku hands you) and the fresh-install gotcha that trips people up on their first deploy. Read this when you're ready to build one.

## Part 3: Living with it

**[`remote`: A Thin CLI That Makes Dokku and Craft CMS Feel Local](/posts/remote-cli-makes-dokku-feel-local/)**

The payoff. Self-hosting's one real cost is that routine operations turn into verbose SSH incantations, with production and staging separated by a single fat-fingerable word. This post is the fix: a small CLI that turns every one of those commands into `remote <env> <verb>`, bakes guardrails in front of the dangerous ones, and unlocks a couple of workflows raw SSH can't manage, like hot-patching a running container and resetting opcache without undoing the patch. Read this to turn a viable setup into a genuinely good one.

## Where to start

If you're weighing the approach, read Part 1 and stop there until you've decided. If you've already decided and want to build, Part 2 is your checklist. And once you have something running, Part 3 is what makes it a pleasure rather than a chore.

The throughline across all three is the same: hosting you understand top to bottom, on a box you control, for a fraction of what the managed alternatives cost. None of it is magic. It's a handful of mature tools composed carefully, and this series is the careful part written down.

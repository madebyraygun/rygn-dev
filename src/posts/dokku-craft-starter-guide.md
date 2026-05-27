---
title: "A Dokku-for-Craft Starter Guide: From a Fresh VPS to a Deployed Site"
date: 2026-05-24
description: "The hands-on part of the series: nine steps from a bare Ubuntu VPS to a deployed Craft site with MySQL, Redis, automatic TLS, a real queue worker, and a staging environment alongside it."
---
{% seriesNav "craft-on-dokku", page.url %}

[The first post in this series](/posts/why-we-host-craft-on-dokku/) made the case for hosting Craft CMS on Dokku and a bare VPS. This one is the hands-on part: how to take a fresh Linux box and a Craft project in git, and end up with a deployed site that has MySQL, Redis, TLS, and a real queue worker. [The next post](/posts/remote-cli-makes-dokku-feel-local/) covers the CLI we use to live with it day to day.

I'm assuming a few things. You have a Craft project you can already run locally, a VPS running a recent Ubuntu LTS with at least a couple of gigs of RAM, and a domain you can point at it. Everything below runs on the server unless I say otherwise, and where I use `mysite` as the app name and `example.com` as the domain, swap in your own.

One note before we start. Craft serves out of a `web/` directory by default, and that's what I'll use throughout. Some projects rename it to `public/`, so if yours differs, just substitute your real webroot wherever it shows up.

## Step 1: Install Dokku

Dokku ships a bootstrap script. As of this writing the current release is v0.38.7:

```bash
wget -NP . https://dokku.com/install/v0.38.7/bootstrap.sh
sudo DOKKU_TAG=v0.38.7 bash bootstrap.sh
```

That installs Docker if it isn't already there, then Dokku itself. Two pieces of global setup follow. First, give yourself push access by registering your SSH public key:

```bash
cat ~/.ssh/authorized_keys | sudo dokku ssh-keys:add admin
```

Then set the global domain, so apps get a sensible default hostname:

```bash
dokku domains:set-global example.com
```

Point an A record for your app's hostname at the server's IP while you're thinking about it. You'll need DNS resolving before the TLS step works.

## Step 2: Create the app and its services

An app is one command:

```bash
dokku apps:create mysite
```

Now the data services. MySQL and Redis are official plugins, installed once on the host:

```bash
sudo dokku plugin:install https://github.com/dokku/dokku-mysql.git mysql
sudo dokku plugin:install https://github.com/dokku/dokku-redis.git redis
```

Create a database and a cache, then link each to the app:

```bash
dokku mysql:create mysite-db
dokku mysql:link mysite-db mysite

dokku redis:create mysite-cache
dokku redis:link mysite-cache mysite
```

Linking does the useful part. It injects a connection string into the app as a config var: `mysql:link` sets `DATABASE_URL`, `redis:link` sets `REDIS_URL`, both pointing at the service's internal hostname. The next step is teaching Craft to read them.

## Step 3: Point Craft at the services

Here's the one genuine impedance mismatch in the whole process. Dokku hands you a single `DATABASE_URL` like `mysql://user:pass@dokku-mysql-mysite-db:3306/mysite_db`, but Craft wants discrete connection settings. The cleanest fix is to parse the URL in `config/db.php`:

```php
<?php
use craft\helpers\App;

$url = parse_url(App::env('DATABASE_URL') ?: '');

return [
    'driver'   => 'mysql',
    'server'   => $url['host'] ?? '127.0.0.1',
    'port'     => $url['port'] ?? 3306,
    'database' => isset($url['path']) ? ltrim($url['path'], '/') : '',
    'user'     => $url['user'] ?? '',
    'password' => $url['pass'] ?? '',
];
```

That keeps working even when the service credentials rotate, because you're always reading whatever Dokku injected.

Redis is optional, but worth doing, since it moves Craft's cache, sessions, and queue out of the database. It needs the `yii2-redis` package (`composer require yiisoft/yii2-redis`), and then a `config/app.php` that parses `REDIS_URL` the same way:

```php
<?php
use craft\helpers\App;

$redis = parse_url(App::env('REDIS_URL') ?: 'redis://localhost:6379');

return [
    'components' => [
        'redis' => [
            'class'    => yii\redis\Connection::class,
            'hostname' => $redis['host'] ?? 'localhost',
            'port'     => $redis['port'] ?? 6379,
            'password' => $redis['pass'] ?? null,
        ],
        'cache' => [
            'class'     => yii\redis\Cache::class,
            'keyPrefix' => App::env('CRAFT_APP_ID') ?: 'CraftCMS',
        ],
        'queue' => [
            'class' => yii\queue\redis\Queue::class,
            'redis' => 'redis',
        ],
    ],
];
```

The rest of Craft's required settings are plain config vars. Set them on the app:

```bash
dokku config:set --no-restart mysite \
  CRAFT_ENVIRONMENT=production \
  CRAFT_APP_ID=<your-app-id> \
  CRAFT_SECURITY_KEY=<your-security-key> \
  CRAFT_DEV_MODE=false \
  CRAFT_ALLOW_ADMIN_CHANGES=false
```

Generate the app ID and security key locally with `php craft setup/app-id` and `php craft setup/security-key` if you don't have them yet. Turning off admin changes in production is the standard Craft setup: project config flows in from git, not from edits on the live server.

## Step 4: Make the project deployable

Dokku builds your app with the PHP buildpack, which reads three things from your repo.

First, `composer.json` declares the PHP version and extensions, which the buildpack provisions for you. Craft already lists its own requirements, so usually this is just confirming a sane PHP constraint is present:

```json
{
  "require": {
    "php": ">=8.2",
    "ext-gd": "*",
    "ext-intl": "*"
  }
}
```

Second, a `Procfile` declares your processes:

```
# Procfile
web:     heroku-php-nginx -C conf/nginx.conf web/
worker:  php craft queue/listen --verbose
release: php craft up --interactive=0
```

The `web` process serves the app, and the `-C conf/nginx.conf` flag is the part Craft specifically needs (it points at the config in the next paragraph). The `worker` process is the dedicated queue runner. And `release` runs on every deploy, after the image is built but before the new container takes traffic, which is exactly where `craft up` belongs: it applies pending migrations and your project config in one step.

Third, that custom nginx config. The buildpack handles PHP-FPM for you, so all you're adding is Craft's front-controller routing, so requests for pretty URLs fall through to `index.php`:

```nginx
# conf/nginx.conf
location / {
    try_files $uri $uri/ /index.php?$query_string;
}
```

While you're adding files, an `app.json` gives you scheduled tasks. Craft's garbage collection is the obvious one:

```json
{
  "cron": [
    { "command": "php craft gc", "schedule": "@daily" }
  ]
}
```

## Step 5: Decide where assets live

Deploys replace the whole container, so anything written to the container's filesystem at runtime is gone on the next release. User-uploaded assets need somewhere durable.

For most sites I'd reach for object storage. Put your asset volumes in an S3-compatible bucket (we use Cloudflare R2) with the matching Craft storage plugin, and the question disappears. Your container stays stateless, which is exactly what you want.

If you'd rather keep assets on the box, mount a persistent directory instead. The host path has to exist first:

```bash
dokku storage:ensure-directory mysite-uploads
dokku storage:mount mysite /var/lib/dokku/data/storage/mysite-uploads:/app/web/uploads
```

Mount the specific uploads path, not Craft's whole `storage/` directory, since the image needs to manage its own runtime files.

## Step 6: Deploy

Deploys are a git push. On your local machine, add the server as a remote and push:

```bash
git remote add dokku dokku@example.com:mysite
git push dokku main
```

Dokku builds the image, runs the `release` process, and swaps the new container in. There's one wrinkle on a brand-new site: `craft up` expects Craft to already be installed, and your fresh database isn't. Run the install once, as a one-off, after the first push:

```bash
dokku run mysite php craft install \
  --username=admin --email=you@example.com \
  --password=<password> --site-name="My Site" --site-url=https://example.com
```

After that, every deploy's `release` step keeps the database and project config in sync on its own. (If you're migrating an existing site rather than starting fresh, you'd load your real database instead of installing, which is exactly what `remote <env> db push` in the next post is for.)

## Step 7: Turn on HTTPS

Point the app at its hostname, then let the Let's Encrypt plugin handle the certificate:

```bash
sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git

dokku domains:set mysite example.com
dokku letsencrypt:set mysite email you@example.com
dokku letsencrypt:enable mysite
sudo dokku letsencrypt:cron-job --add
```

The `cron-job` line is the one people forget. Without it your certificate is good for ninety days and then quietly expires. With it, renewals take care of themselves.

## Step 8: Run the queue worker

The `worker` process is in your Procfile, but Dokku won't run it until you ask for one:

```bash
dokku ps:scale mysite worker=1
```

Now a dedicated process is draining Craft's queue, instead of leaning on web requests to nudge it along.

## Step 9: Add a staging app

This is the payoff from the first post. A second environment is just another app on the same box:

```bash
dokku apps:create mysite-staging
dokku mysql:create mysite-staging-db && dokku mysql:link mysite-staging-db mysite-staging
dokku redis:create mysite-staging-cache && dokku redis:link mysite-staging-cache mysite-staging
dokku domains:set mysite-staging staging.example.com
dokku letsencrypt:enable mysite-staging
```

Add a second git remote pointing at `mysite-staging`, push to it, and you have a staging copy that costs nothing beyond the disk and memory it actually uses.

## Where this leaves you

At this point you have a real, deployed Craft site: git-push deploys that run your migrations and project config, a queue worker, Redis-backed caching, automatic TLS, and a staging environment alongside it. All of it on one box you own.

What you'll notice almost immediately is that operating it means a lot of `ssh example.com "dokku run mysite ..."` and `dokku config:set` typing, with production and staging separated by a single word. That's the friction [the next post](/posts/remote-cli-makes-dokku-feel-local/) is about. The `remote` CLI turns every command here into `remote <env> <verb>` and puts a guardrail in front of the dangerous ones, so the setup you just built is genuinely pleasant to live with.

---

*This is the hands-on installment of a series on hosting Craft CMS the way we actually do it. It follows [the case for Dokku on a bare VPS](/posts/why-we-host-craft-on-dokku/), and leads into [the `remote` CLI](/posts/remote-cli-makes-dokku-feel-local/) that makes day-to-day operations painless.*

# Testing push notifications locally

MN-D03. How to get a push notification to arrive on your own machine, and then on
a real phone.

This does not cover generating VAPID keys, registering a browser by hand, or what
the payload looks like. That is all in
[`push-setup.md`](./push-setup.md), in this same folder. Read that first. This document is only about the two
things it does not answer: why push works on `localhost` with no HTTPS, and why it
stops working the moment you point a phone at your laptop.

Every section is marked **Verified** or **Not tested**. Read those marks. The
tunnel half of this guide has not been walked end to end by anyone yet, so treat
section 3 as a route rather than a proven path and correct it as you go.

---

## 0. Push does nothing without MN-F03

**Verified** — read from web#4, `push/enable-service-worker-in-dev`, merged into
`feature/notifications` in `doubtfire-web` on 8 Aug 2026.

A service worker is the thing that receives a push. Before MN-F03, `angular.json`
set `"serviceWorker": "ngsw-config.json"` only on the `production` build
configuration, so a development build never generated `ngsw-worker.js` at all.
The browser had nothing to receive a push with, and the failure was silent.

MN-F03 changed two files:

```diff
  "development": {
    "optimization": false,
    "extractLicenses": false,
-   "sourceMap": true
+   "sourceMap": true,
+   "serviceWorker": "ngsw-config.json"
  },
```

```diff
  ServiceWorkerModule.register('ngsw-worker.js', {
-   enabled: environment.production,
+   enabled: environment.production || environment.enableServiceWorker,
    registrationStrategy: () => interval(6000).pipe(take(1)),
  }),
```

plus `enableServiceWorker: true` in `src/environments/environment.ts`.

**If you are on a branch that does not have MN-F03, nothing in this guide will
work and you will get no error telling you why.** Check before you start:

    curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4200/ngsw-worker.js

200 means you have it. 404 means you do not. Full detail, including the six second
registration delay and the `$NODE_ENV` trap, is in
`docs/service-worker.md` in the `doubtfire-web` repo, on `feature/notifications`.

---

## 1. `http://localhost` is a secure context, so localhost needs no HTTPS

**Verified** — behaviour recorded in `doubtfire-web/docs/service-worker.md` on
2026-08-02, where a push sent from the api arrived as a desktop notification on
`http://localhost:4200`. I did not re-run it for this guide.

Service workers and the Push API are restricted to secure contexts. People read
that as "I need HTTPS" and go and generate a self-signed certificate, or set up
mkcert, or ask why the dev stack does not do TLS. **None of that is necessary.**

The rule is not "must be HTTPS". It is "must be a *potentially trustworthy
origin*", and loopback addresses are on that list by definition. So all of these
are secure contexts:

- `http://localhost:4200`
- `http://localhost` on any port
- `http://127.0.0.1:4200`
- `http://[::1]:4200`

Which means the ordinary dev stack, `ng serve` on port 4200 over plain HTTP, is
already good enough to register a service worker, subscribe to push, and receive
a push. Do this part first. It is the fast loop, and if push does not work here it
will not work anywhere else either.

Order of work:

1. `curl` `/ngsw-worker.js` and get a 200 (section 0).
2. Follow `push-setup.md` to confirm the keys are loaded and subscribe the browser.
3. Trigger an event, get a notification on your desktop.

Only once that works should you go anywhere near a tunnel.

---

## 2. The trap: a phone on your wifi is not a secure context

**Verified on a physical phone.** MN-Q03 reproduced this on an iPhone 16
running iOS 26.6 on 13 Aug 2026. The phone reached the api over the LAN
address, but the push opt-in remained disabled because the page was not a
secure context.

`angular.json` sets the dev server to `"host": "0.0.0.0"`, so `ng serve` listens
on every interface, not just loopback. Your laptop's LAN address works. You can
type `http://192.168.1.42:4200` into a phone on the same wifi and the OnTrack app
loads, logs in, and behaves completely normally.

**And push will not work, and nothing will tell you why.**

`192.168.1.42` is not a loopback address. It is a plain HTTP origin like any
other, so it is not a secure context, so `navigator.serviceWorker` is not even
defined on that page. Practically:

- No service worker registers.
- `SwPush.isEnabled` is `false`, so MN-C01's opt-in button reports "not
  supported" rather than an error.
- `Notification.requestPermission()` may still work, which makes it look like
  permissions are the problem when they are not.
- Nothing appears in the console. There is no exception, no warning, no failed
  request. The feature is just absent.

This is the evening-costing one. The symptom is "it works on my laptop but not on
my phone", and the instinct is to go and debug the subscription code, the VAPID
key, the api logs, notification permissions on the phone. All of that is fine. The
page is simply not a secure context.

Quick check, in the phone's browser console or as a bookmarklet:

```js
console.log(window.isSecureContext, 'serviceWorker' in navigator);
```

`false false` on the LAN address, `true true` through a tunnel. If you only take
one thing from this document, take that line.

**Testing on a real phone therefore needs real HTTPS, which means a tunnel.**

### iOS is a second trap on top of the first

**Not tested.** Documented Safari behaviour, included because it will come up.

Safari on iOS only supports Web Push for web apps that have been added to the
Home Screen. Opening the tunnel URL in Safari and expecting a push will fail even
over HTTPS. The user has to Share → Add to Home Screen and open it from there.
Android Chrome has no such restriction. If you are picking a phone to test with,
pick Android.

---

## 3. Tunnel setup with cloudflared

**Not tested.** `cloudflared` is not installed on this machine and I have not run
any of this. The steps below are written from the tool's documented behaviour and
from configuration I did verify in our repos (each config change is marked
separately). Treat the sequence as a first draft that needs someone to walk it.

I picked `cloudflared` over `ngrok` because a quick tunnel needs no account, no
signup and no authtoken. `ngrok` now requires an account before it will forward
anything. One tool, done properly, rather than two done badly.

### Why one tunnel is enough

**Verified** — read from `doubtfire-web/src/app/config/constants/hostUrl.ts` and
`doubtfire-web/proxy.conf.json`.

The obvious worry is that you need two tunnels, one for the web app on 4200 and
one for the api on 3000, and that the phone would load an HTTPS page that then
tries to call `http://localhost:3000` and gets blocked as mixed content.

That does not happen, because of two things already in the repo:

```ts
// src/app/config/constants/hostUrl.ts
const HOST_URL: string = `${window.location.protocol}//${window.location.hostname}${window.location.port ? ':' + window.location.port : ''}`;
```

The app derives its api base URL from wherever the page was loaded from. It is not
hardcoded. And `package.json` runs `ng serve ... --proxy-config proxy.conf.json`,
which forwards `/api` to the api container:

```json
{ "/api": { "target": "http://localhost:3000", "secure": false } }
```

So the browser only ever talks to one origin. Tunnel port 4200 and the api comes
along with it. **Do not tunnel port 3000 as well.** It will not help and it gives
you a second hostname to get wrong.

### Step 1 — install cloudflared

    brew install cloudflared

### Step 2 — have the stack running on localhost first

Section 1. If push does not work on `http://localhost:4200`, a tunnel will not fix
it, it will just add a second thing that can be broken.

### Step 3 — start the tunnel

    cloudflared tunnel --url http://localhost:4200

It prints a hostname that looks like:

    https://random-words-here.trycloudflare.com

That hostname is new every time you restart the tunnel. Which matters, because
both config changes below name it, so **you will be editing config every time you
restart the tunnel.** Leave it running.

### Step 4 — let the Angular dev server answer to that hostname

**Verified** that this option exists and is spelled this way — read from
`node_modules/@angular/build/src/builders/dev-server/schema.json` at version
22.0.4. Not verified that the tunnel then works.

Vite, which is what `@angular/build:dev-server` runs on, rejects requests whose
`Host` header is not in its allowlist. Without this you get a Vite "Blocked
request" page through the tunnel instead of the app.

In `angular.json`, under `projects.doubtfire.architect.serve.options`:

```json
"serve": {
  "builder": "@angular/build:dev-server",
  "options": {
    "buildTarget": "doubtfire:build",
    "port": 4200,
    "host": "0.0.0.0",
    "allowedHosts": ["random-words-here.trycloudflare.com"]
  },
```

Changing `angular.json` does not update the already-running dev server. Restart
the web service before opening the tunnel hostname. Run this from
`doubtfire-deploy/development`:

    docker compose -f docker-compose.yml -f docker-compose.local-paths.yml \
      restart doubtfire-web

If the frontend is running directly with `npm start`, stop it and start it again
instead.

The schema also accepts `"allowedHosts": true` to allow everything. Its own
description calls that "not recommended and a security risk", which is fair, since
your dev server is on the public internet for as long as the tunnel is up. Use it
if you are restarting the tunnel constantly and are sick of editing this file, but
do not commit it.

**Do not commit any of this.** It is a hostname that will not exist tomorrow.

### Step 5 — let the api answer to that hostname

**Verified** — I reproduced the failure directly against the running api
container:

```
$ curl -s -H "Host: probe-test.trycloudflare.com" http://localhost:3000/api/settings
Blocked hosts: probe-test.trycloudflare.com
To allow requests to these hosts, make sure they are valid hostnames (containing
only numbers, letters, dashes and dots), then add the following to your
environment configuration:
config.hosts << "probe-test.trycloudflare.com"
```

The same request with the default `Host` returns 200.

This is Rails 8 Host Authorization, not CORS. In development Rails allows loopback
addresses, any raw IP, and anything ending in `.localhost` or `.test`. A
`trycloudflare.com` hostname is none of those, so the api rejects it before any
of our code runs.

The fix that needs no code change, in `doubtfire-deploy/development/docker-compose.yml`
under `doubtfire-api.environment`:

```yaml
      RAILS_DEVELOPMENT_HOSTS: 'random-words-here.trycloudflare.com'
```

**Verified** that Rails reads this variable and splits it on commas — railties
8.0.2, `lib/rails/application/configuration.rb`. Comma separate if you need more
than one.

Then recreate the container. `restart` does not pick up new environment
variables, same as with the VAPID keys:

    docker compose -f docker-compose.yml -f docker-compose.local-paths.yml up -d doubtfire-api

Confirm it took:

    curl -s -o /dev/null -w "%{http_code}\n" \
      -H "Host: random-words-here.trycloudflare.com" \
      http://localhost:3000/api/settings

### About CORS, which is not your problem

**Verified** — read from `doubtfire-api/config/application.rb:287`.

    config.middleware.insert_before Warden::Manager, Rack::Cors do
      allow do
        origins '*'
        resource '*', headers: :any, methods: %i(get post put delete options)
      end
    end

Origins is already `*`. **There is no CORS change to make for a tunnel.** And
because of the dev server proxy in step 3, the api calls are same-origin anyway,
so CORS is not even in play. If you are looking at a CORS error you have found a
different bug. The api-side change you actually need is `RAILS_DEVELOPMENT_HOSTS`
above.

### An alternative to step 5 that I have not tried

**Not tested.** Setting `"changeOrigin": true` on the `/api` entry in
`proxy.conf.json` should make the proxy rewrite the `Host` header to
`localhost:3000` before forwarding, so Rails never sees the tunnel hostname and
`RAILS_DEVELOPMENT_HOSTS` becomes unnecessary. That would survive tunnel restarts,
which is the appeal.

I did not test it, and I did not confirm what the proxy's default actually is.
`RAILS_DEVELOPMENT_HOSTS` is the one I verified fails and can be made to pass, so
that is what step 5 says. If you try `changeOrigin`, note that in the Docker stack
`doubtfire-deploy/development/docker-compose.local-paths.yml` mounts
`proxy.conf.docker.json` over the repo's `proxy.conf.json` read-only, so you have
to edit the deploy repo's copy, not the web repo's.

### Step 6 — open it on the phone

Open the printed `https://...trycloudflare.com` URL on the phone. Check the secure
context first, before anything else:

```js
window.isSecureContext && 'serviceWorker' in navigator
```

Before subscribing on the phone, record the existing rows:

    docker exec doubtfire-api bundle exec rails runner \
      'puts PushSubscription.order(:id).map { |s| "#{s.id} #{s.user.username} #{s.endpoint[0, 80]}" }'

Then sign in, wait out the six second service worker registration delay, and use
MN-C01's opt-in button. Run the same command again. The new or changed row is
the phone's subscription.

Do not identify the device only from the endpoint host. It narrows the browser
but it does not name the device, and Chromium does not imply one service:
measured on 27 Aug 2026, Chrome 152 subscribed through `fcm.googleapis.com` and
Edge 151 on macOS through `wns2-bl2p.notify.windows.com`. Firefox uses Mozilla
Push and Safari/iOS uses Apple Web Push. Comparing the rows before and after
subscribing is the reliable check. Then trigger an event as another user and
watch.

### Things that will probably go wrong

**Not tested.** Written from what the configuration implies, not from experience.

- **Vite's HMR websocket may not survive the tunnel.** The page still loads, live
  reload just stops. Not worth fixing for a push test, reload by hand.
- **The tunnel hostname changes on every restart**, and both step 4 and step 5
  name it. If push worked yesterday and does not today, check that first.
- **A quick tunnel is public.** Anyone with the URL reaches your dev stack with
  its throwaway VAPID keys and seeded database. Stop it when you are done.
- **You will have two subscriptions for your user**, one from the desktop test and
  one from the phone. Both get pushed. That is correct behaviour, not a bug.

---

## 4. Clearing a stuck service worker

**Not tested** in Firefox. The Chrome console snippet is taken from
`doubtfire-web/docs/service-worker.md`, which is where the fuller writeup of the
service worker's caching side effects lives.

A service worker caches the whole app bundle and keeps serving it. The symptom is
that you change code, reload, and still see the old code. A hard reload does not
help, because the worker still intercepts the request.

### Both browsers, from the console

Works in Chrome and Firefox. Faster than the UI and the one to reach for at 1am:

```js
(await navigator.serviceWorker.getRegistrations()).forEach((r) => r.unregister());
const keys = await caches.keys();
await Promise.all(keys.map((k) => caches.delete(k)));
location.reload();
```

### Chrome, through dev tools

1. F12 → **Application** → **Service Workers**.
2. **Unregister** next to `ngsw-worker.js`.
3. **Application** → **Storage** → **Clear site data**.
4. Reload.

While you are actively working on the app, **Application → Service Workers →
Bypass for network** stops the worker serving cached responses without
unregistering it. That is usually what you want during normal development. It is a
per-devtools-session setting and it resets when you close dev tools.

`chrome://serviceworker-internals` lists every registration in the profile and
will unregister them, which is the one to use when a worker is stuck on an origin
you no longer have open.

### Firefox, through dev tools

1. F12 → **Application** → **Service Workers**.
2. **Unregister**.
3. **Storage** → right click the origin → **Delete All**.
4. Reload.

`about:debugging#/runtime/this-firefox` is the equivalent of Chrome's
`serviceworker-internals` and has **Unregister** buttons per worker.

Firefox private windows do not run service workers at all, so push cannot work
there. Do not use one to test.

---

## 5. Resetting notification permission

**Not tested.** Written from the current browser UIs. Someone should walk these
and correct them.

Permission is per origin, and once denied the browser will not ask again. The
opt-in button will report "blocked" forever and no amount of clicking will
prompt. You have to reset it by hand. Everyone denies it by accident once.

Check where you stand, in the console:

```js
Notification.permission          // "default" | "granted" | "denied"
```

`default` means you will be prompted. `denied` means you will not.

### Chrome

Fastest: click the icon at the left of the address bar (the tune or lock icon),
find **Notifications**, set it back to **Ask (default)**. Reload.

Or `chrome://settings/content/notifications`, find the origin under **Not allowed
to send notifications**, and remove it. Whole-origin nuke, which also clears the
service worker and everything else, is **Clear site data** in the same panel.

Two things that are not the same as the browser permission and get confused with
it:

- **macOS System Settings → Notifications → Google Chrome.** If Chrome itself is
  not allowed to post notifications, the browser permission can be `granted` and
  the push can arrive and you still see nothing. `push-setup.md` calls this out
  too. Check it once, then stop thinking about it.
- **Focus / Do Not Disturb.** Same result, notifications delivered silently to
  Notification Centre.

### Firefox

Click the padlock in the address bar → **Clear cookies and site data**, or expand
**Connection secure** → **More information** → **Permissions**, find **Receive
Notifications**, and untick **Use Default** then set it back.

Or `about:preferences#privacy` → **Permissions** → **Notifications** →
**Settings**, find the origin, **Remove Website**. Reload.

Check `about:preferences#privacy` → **Notifications** → **Settings** for **Block
new requests asking to allow notifications** as well. If that is ticked, nothing
will ever prompt and the state will read `denied` on every site.

### Android Chrome

Site permissions are under the padlock → **Permissions** → **Notifications**. But
also check Android **Settings → Apps → Chrome → Notifications**, because if
Chrome as an app is blocked at the OS level then no site inside it can post
anything, and the in-page permission will still say `granted`.

---

## Verification status, all in one place

| Section | Status |
|---|---|
| MN-F03 is required, and what it changed | **Verified.** Read from the web#4 diff, merged 8 Aug 2026. |
| `http://localhost` is a secure context | **Verified.** Recorded working in `doubtfire-web/docs/service-worker.md`, 2026-08-02. Not re-run here. |
| A LAN address is not a secure context | **Verified on a physical phone.** iPhone 16 / iOS 26.6, 13 Aug 2026, MN-Q03. The phone reached the api over the LAN address but the opt-in button was disabled with "This browser does not support push notifications". |
| iOS needs Add to Home Screen | **Not tested.** Documented Safari behaviour. |
| One tunnel is enough, because of `hostUrl.ts` + the dev server proxy | Config **verified** by reading it. The conclusion is an inference, **not tested**. |
| `cloudflared` install and tunnel steps | **Not tested.** `cloudflared` is not installed on this machine. |
| `allowedHosts` is a real dev server option | **Verified** against `@angular/build` 22.0.4's schema. Effect through a tunnel **not tested**. |
| Rails blocks a tunnel hostname | **Verified.** Reproduced with `curl -H "Host: ..."` against the running api. |
| `RAILS_DEVELOPMENT_HOSTS` is the variable Rails reads | **Verified** in railties 8.0.2 source. Not tested end to end through a tunnel. |
| No CORS change is needed | **Verified.** `origins '*'` at `config/application.rb:287`. |
| `changeOrigin` as an alternative | **Not tested.** Offered as a lead, not a step. |
| Clearing a service worker | Console snippet from `service-worker.md`. Chrome and Firefox UI paths **not tested**. |
| Resetting notification permission | **Not tested**, all browsers. |

Section 2 has now been walked. MN-Q03 hit exactly the failure this guide
predicts, on an iPhone 16 running iOS 26.6 on 13 Aug 2026. The phone reached the
api fine over the LAN address and the opt-in button was still disabled, which is
the browser refusing to expose the push API outside a secure context. So the
rule holds on real hardware and not just on paper.

Section 3, the tunnel, is still unwalked. Nobody has yet run `cloudflared` end
to end and got a push onto a phone. That is what MN-Q02 and the retest of MN-Q03
are for, and a screenshot of a notification arriving on a real lock screen is
the deliverable that closes them.

If you are the first person through section 3, correct this document as you go
rather than working around it. Every step in there was reasoned from config
rather than executed, and the marks in the table above say which is which.

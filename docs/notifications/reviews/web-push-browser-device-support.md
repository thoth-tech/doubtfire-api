# Web Push support by browser and device

MN-D04. Support position checked 23 August 2026.

## Answer first: can an iPhone receive OnTrack push?

Yes, on iOS or iPadOS 16.4 or later, but only from a Home Screen web app. The
user must add OnTrack to the Home Screen, open that installed app instead of an
ordinary browser tab, tap OnTrack's enable control, and grant notification
permission. This applies whether Safari, Chrome, Edge, or Firefox added the web
app: Apple made Add to Home Screen available to third-party browsers, and the
installed web app runs separately from the browser that added it.

An iPhone user who only opens OnTrack in a browser tab cannot receive its Web
Push notifications. MN-W01's installable manifest and MN-W03's visible iOS
installation instructions are therefore prerequisites, not optional polish.

## Requirements common to every supported entry

OnTrack delivery needs all of the following:

1. A secure context. Production needs HTTPS; `http://localhost` is a special
   development exception. A phone opening a laptop's plain HTTP LAN address is
   not a secure context.
2. An active service worker and the Push and Notifications APIs.
3. A direct user action on OnTrack's enable control, followed by permission from
   the browser or operating system.
4. A VAPID-backed `PushSubscription` stored by the authenticated
   `/api/push_subscriptions` endpoint.
5. Permission for the browser or installed web app at operating-system level.
6. A subscription endpoint whose host passes OnTrack's server allowlist.

Installation is not normally required for desktop or Android Web Push. It is a
hard requirement on iOS and iPadOS.

## Browser and platform matrix

"Supported" describes the browser platform, not a completed OnTrack device
test. MN-Q01 and MN-Q02 own observed delivery evidence.

| Browser | Platform   | Web Push                                                                    | What it requires                                                                                                        | Important catch for OnTrack                                                                                                                                                                                                                |
| ------- | ---------- | --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Chrome  | Desktop    | Supported                                                                   | Current Chrome, secure context, service worker, user-granted notification permission                                    | Chrome subscriptions normally use `fcm.googleapis.com`, which OnTrack accepts. The browser may need to remain allowed to run in the background for delivery after its windows close.                                                       |
| Chrome  | Android    | Supported                                                                   | Current Chrome on Android and the common requirements above; installation is optional                                   | Uses Google's push infrastructure. OnTrack accepts current `fcm.googleapis.com` and legacy `android.googleapis.com` endpoints. Android may separately mute Chrome or the site.                                                             |
| Chrome  | iOS/iPadOS | Supported only as an installed Home Screen web app on 16.4+                 | Add from Chrome's Share menu, open from the Home Screen, then enable push from a user gesture                           | No push from a normal Chrome tab. The installed app uses Apple's Web Push path, not Chrome/FCM. Its endpoint must match OnTrack's Apple allowlist.                                                                                         |
| Edge    | Desktop    | Supported                                                                   | Current Microsoft Edge, secure context, service worker, VAPID, and user permission                                      | Depending on platform/version, an endpoint may use Google or Microsoft infrastructure. OnTrack accepts FCM, `*.push.services.microsoft.com`, and legacy `*.notify.windows.com`. Capture the actual host in MN-Q01.                         |
| Edge    | Android    | Supported by the current Edge PWA platform; OnTrack not yet device-verified | Current Edge on Android and the common requirements; installation is optional                                           | Microsoft documents PWA capabilities across devices but does not promise which push-service host a given mobile build returns. OnTrack will reject a new host until it is reviewed and allowlisted.                                        |
| Edge    | iOS/iPadOS | Supported only as an installed Home Screen web app on 16.4+                 | Add from Edge's Share menu, open the installed app, then enable push from a user gesture                                | No push from an ordinary Edge tab. Apple's Home Screen web-app rules and endpoint compatibility apply.                                                                                                                                     |
| Firefox | Desktop    | Supported                                                                   | Current Firefox, secure context, service worker, and user-granted permission                                            | Firefox uses Mozilla's push service. OnTrack accepts `updates.push.services.mozilla.com`. Firefox must be running for desktop delivery according to Mozilla's user documentation.                                                          |
| Firefox | Android    | Supported                                                                   | Current Firefox for Android, site notification permission, Android notification permission, and the common requirements | Mozilla routes Firefox Android Web Push through its service plus Google Cloud Messaging. The subscription endpoint still needs to be one OnTrack accepts; record it during device testing.                                                 |
| Firefox | iOS/iPadOS | Supported only through an installed Home Screen web app on 16.4+            | Add from the Share menu, open the installed web app, then enable push from a user gesture                               | Do not treat Firefox's ordinary iOS tab as the receiver. Once installed, the Home Screen web app is a separate WebKit app and uses Apple's Web Push path.                                                                                  |
| Safari  | Desktop    | Supported on macOS Ventura with Safari 16.1 or later                        | Secure context, service worker, standards-based Web Push/VAPID, and user permission                                     | No Apple Developer Program membership is required. OnTrack accepts Apple's documented `*.push.apple.com` endpoint namespace.                                                                                                             |
| Safari  | Android    | Not available                                                               | Safari is not released for Android                                                                                      | Use Chrome, Edge, or Firefox and verify the endpoint host.                                                                                                                                                                                 |
| Safari  | iOS/iPadOS | Supported only as an installed Home Screen web app on 16.4+                 | Share → Add to Home Screen, open the installed app, tap OnTrack's enable control, then grant permission                 | This is the key platform limitation. No installed app means no Push API permission prompt and no delivery. Focus, Lock Screen, and per-app notification settings can still suppress display.                                               |

## OnTrack's endpoint allowlist is a second compatibility gate

Browser support alone is not enough. `PushSubscription` rejects an endpoint
unless its HTTPS host is one of these exact hosts:

- `fcm.googleapis.com` — Chrome and Chromium-family delivery.
- `android.googleapis.com` — older Chrome on Android.
- `updates.push.services.mozilla.com` — Firefox.

It also accepts subdomains ending in:

- `.notify.windows.com` — legacy Windows Notification Service endpoints.
- `.push.services.microsoft.com` — current Microsoft push-service endpoints.
- `.push.apple.com` — Safari and iOS/iPadOS Web Push endpoints.

The suffix check includes the leading dot, so a lookalike such as
`evil-notify.windows.com` does not pass. Delivery repeats the check for rows
created before the model validation existed.

This is deliberately stricter than "the browser implements Push API". A new
browser version can support Web Push and still receive HTTP 400 from OnTrack if
its vendor starts returning a host outside this list. Record the endpoint host
in every manual browser/device test. Review a new host against vendor
documentation before adding it; never broaden the validation just to make a
test pass.

Apple endpoints are matched with the boundary-aware `.push.apple.com` suffix.
That accepts hosts in Apple's documented namespace without accepting lookalikes
such as `evilpush.apple.com` or `web.push.apple.com.example.org`.

## What this table does not claim

- `.browserslistrc` says which JavaScript targets Angular compiles for. It is
  not evidence that a browser/OS can subscribe, receive, display, and navigate
  from a push.
- API presence or a successful subscription is not delivery evidence. The
  operating system can mute an otherwise valid subscription.
- iOS browser branding is not a way around the Home Screen rule.
- An Android emulator is useful for layout and permission-flow checks, but does
  not satisfy MN-Q02's requirement for a real-phone Lock Screen delivery.

## Primary sources

- Apple WebKit, [Web Push for Web Apps on iOS and iPadOS](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/) — iOS/iPadOS 16.4, Home Screen requirement, direct user interaction, Lock Screen delivery, Apple push service, and third-party Add to Home Screen.
- Apple WebKit, [Meet Web Push](https://webkit.org/blog/12945/meet-web-push/) — standards-based Web Push in Safari on macOS Ventura and no Apple Developer Program requirement.
- Apple WebKit, [WebKit Features in Safari 18.4](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/) — confirms standard Web Push shipped in Safari 16.1 on macOS and iOS/iPadOS 16.4.
- Google web.dev, [Push notifications overview](https://web.dev/articles/push-notifications-overview) — permission, subscription, service-worker, browser push-service, and FCM endpoint flow.
- Microsoft Edge, [Re-engage users with push messages](https://learn.microsoft.com/en-us/microsoft-edge/progressive-web-apps/how-to/push) — Edge permission, Push API, VAPID, user-visible requirement, and service-worker delivery.
- Microsoft Edge, [Use Progressive Web Apps in Microsoft Edge](https://learn.microsoft.com/en-us/microsoft-edge/progressive-web-apps/ux) — current device-wide PWA capability position.
- Mozilla Support, [Web Push notifications in Firefox](https://support.mozilla.org/en-US/kb/push-notifications-firefox) — Firefox desktop delivery, Mozilla push service, permissions, and Android routing.
- Mozilla Support, [Manage notifications in Firefox for Android](https://support.mozilla.org/en-US/kb/manage-notifications-firefox-android) — Android site-notification permission control.
- Mozilla Source Docs, [Push](https://firefox-source-docs.mozilla.org/dom/push/) — Firefox and Firefox for Android implementation paths.
- MDN, [Push API](https://developer.mozilla.org/en-US/docs/Web/API/Push_API) and [Secure contexts](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts) — platform API and secure-context baseline.

## Follow-up verification

Use `testing-push-locally.md`, then record for each tested row: operating system,
browser version, secure-context result, permission state, returned endpoint host,
API row, real event, displayed title/body, click destination, and cleanup. A
failure should become its own bug with reproduction steps rather than being
hidden in this comparison.

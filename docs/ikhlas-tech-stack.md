# Ikhlas — Technology Stack & Rationale

**Context:** India Phase 1 · Solo founder · Flutter + Firebase core · Lean, buy-don't-build outside the moat.
**Guiding principle:** Build only what *is* Ikhlas (the gate, the review funnel, the premium experience). Buy everything else as a managed service so one person can run a company.

---

## The stack at a glance

| Layer | Choice | Why this | What we rejected & why |
|---|---|---|---|
| **App framework** | Flutter | One codebase → iOS + Android; you already build in it; excellent UI control for the premium look | Native (2× the work solo); React Native (you don't work in it) |
| **Backend / BaaS** | Firebase | Turnkey auth, DB, functions, storage, push — no servers to run; you know it | Custom backend (months of work for a solo founder); Supabase (viable, but you're fluent in Firebase) |
| **Database** | Cloud Firestore | Realtime, scales to zero cost at launch, security rules enforce the "no browsing" moat at the data layer | SQL/Postgres (you'd manage it; overkill for launch) |
| **Region** | asia-south1 (Mumbai) | India latency + data residency (DPDP Act comfort) | Any non-India region (residency optics + latency) |
| **Auth** | Firebase Phone OTP (SMS first) → WhatsApp later | Fast to ship; SMS universal; abstracted so WhatsApp is a swap | Email/password (weak for a trust product); social login (wrong register for a nikah app) |
| **SMS OTP** | MSG91 | India-native, does SMS *and* WhatsApp (one vendor, future-proof), DLT-compliant | Twilio (pricier for India, weaker local routes); Firebase native SMS (no template/DLT control) |
| **Selfie liveness** | HyperVerge | India-native passive liveness, strong local coverage, anti-catfishing gate | Sumsub/Onfido (MENA/EU-tuned, pricier for India) |
| **Aadhaar badge (optional)** | Surepass / Cashfree | Aggregator holds AUA/KUA licence; ~₹3/check; returns verified DOB+gender | Direct UIDAI (you'd need to be a licensed AUA — not feasible solo) |
| **AI application triage** | Anthropic API (Haiku-class) | ~₹0.29/application; shrinks your review load ~85%; strong rubric-following | Manual-only (impossible solo at 3,000 apps); cheaper/weaker models (sincerity nuance matters) |
| **Push notifications** | FCM (Firebase Cloud Messaging) | Free, native to Firebase, cross-platform | OneSignal (unneeded third party) |
| **Serverless logic** | Cloud Functions | The gate, review funnel, webhooks, notifications — no server to maintain | Self-hosted Node (ops burden for a solo founder) |
| **File storage** | Firebase Storage | Photos private by default; signed URLs only; watermarking hook | S3 (more setup; you'd leave the Firebase ecosystem) |
| **Wali portal** | Flutter Web or plain HTML/JS on Netlify | Magic-link, no app install for low-tech guardians; you already use Netlify | Native second app (huge overkill for a lightweight portal) |
| **Admin dashboard** | Flutter Web (moderator-gated) | Reuses your Flutter skills + models; one language across the stack | Retool/no-code (monthly cost; less control over the review UI) |
| **Analytics** | Firebase Analytics + Mixpanel | Firebase free & native; Mixpanel for funnel depth (application→approval→match) | GA4 alone (weak for product funnels) |
| **Payments (Phase 2)** | Razorpay | India-standard, UPI + cards + subscriptions; strong for ₹ recurring plans | Stripe (weaker India/UPI support); Play/App Store billing (30% cut — but may be forced for digital goods, see note) |
| **Crash/monitoring** | Firebase Crashlytics | Free, native, essential for a solo founder who can't watch everything | Sentry (fine, but Crashlytics is already there) |

---

## The deliberate philosophy

**1. Firebase as the spine — because you are one person.**
Every hour spent running servers, patching a database, or wiring auth from scratch is an hour not spent on the gate, the review funnel, or talking to your waitlist. Firebase collapses six infrastructure jobs into one managed platform you already know. This is the single highest-leverage choice for a solo founder.

**2. Buy the commodity, build the moat.**
Verification, SMS, liveness, payments, push — these are solved problems. You rent them. What you *build* is the eligibility gate, the three-tier AI review funnel, and the premium experience — because those are Ikhlas and nobody can sell them to you.

**3. India-native vendors, not global defaults.**
HyperVerge over Sumsub, MSG91 over Twilio, Razorpay over Stripe, Mumbai region — not out of habit but because Phase 1 is India, and local vendors win on price, routes, compliance (DLT, AUA/KUA, DPDP), and coverage. When you expand beyond India, you revisit — but you don't pay a global-vendor premium to serve one country.

**4. Abstract the swappable layers.**
Auth channel (SMS↔WhatsApp) and the verification provider sit behind interfaces, so switching is config, not a rewrite. This protects a solo founder from being locked into a Week-1 decision made under time pressure.

**5. Everything defers gracefully.**
Payments, Aadhaar badge, WhatsApp OTP, company incorporation — all Phase-2 or fast-follow. Nothing on the launch-critical path requires money or paperwork you're not ready for, *except* individual DLT registration for SMS (the one unavoidable early step).

---

## One flag worth knowing now: app-store billing

Apple and Google generally require digital subscriptions (your ₹599/₹1,299/₹1,999 plans) to go through **their** billing (Play Billing / StoreKit) and take up to 30% — you often can't route in-app digital-goods payments through Razorpay to avoid the cut. Matrimonial apps navigate this in different ways (some charge on web, some accept the cut). It doesn't affect Phase 1 (no payments at launch), but it's a real Phase-2 economic decision — factor the potential 30% into the pricing you validate. I've noted it so it's not a surprise later.

---

## What's NOT in the stack yet (and why that's correct)

- **No dedicated chat infra** (e.g. Stream, Sendbird) — Phase 2. Guarded chat can run on Firestore at launch scale; revisit a chat SDK only if volume demands it.
- **No search service** (Algolia/Typesense) — the "no browsing" model means there's no user-facing search in v1. Matching is server-generated batches. You may want Algolia for the *admin* dashboard later, not for users.
- **No CDN/media pipeline beyond Firebase** — signed URLs + a resize/watermark function cover launch. Optimize only if photo volume becomes a cost.
- **No Kubernetes, no microservices, no message queue** — a solo founder does not need distributed-systems complexity to serve a launch. Cloud Functions are enough until they aren't, and they won't stop being enough for a long time.

The discipline here is as important as any single choice: **the cheapest, most maintainable system is the one you don't build.**

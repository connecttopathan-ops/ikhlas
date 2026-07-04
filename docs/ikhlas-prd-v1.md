# Ikhlas — Product Requirements & Workflow Document (v1.1)

**Product:** Ikhlas — Islamic matrimonial app for practicing Muslims
**Domain:** ikhlaas.io · **Platform:** Flutter (iOS + Android)
**Launch market:** India (Phase 1) · **Region:** Firebase asia-south1 (Mumbai)
**Status:** Pre-launch (Instagram waitlist live) · **Doc owner:** Ab
**Date:** July 2026

> **v1.1 changelog:** Auth model updated (Google + Email OTP login; phone collected-but-unverified in Phase 1, phone OTP → Phase 2). AI-Assisted Review architecture folded in (§4.5A). Launch market set to India throughout (was UAE/GCC). Verification model finalized (selfie mandatory, Aadhaar optional badge). Open questions #1, #2, #5 resolved. Companion docs: `ikhlas-tech-requirements.md`, `ikhlas-tech-stack.md`, `ikhlas-cost-model.xlsx`, `ikhlas-revenue-forecast.xlsx`.

---

## 1. Product Vision & Positioning

**One line:** The matrimonial app where every single member is verified as serious about nikah — no browsers, no time-wasters, no casual daters.

**The wedge:** Competitive research (Muzz, Salams, HalfOurDeen, IslamicMarriage, Zawjni/Hawaya) confirmed photo privacy and Wali options are table stakes. Ikhlas's differentiator is the **strict eligibility gate**: you cannot enter the pool without passing screening. Everything in this spec serves that positioning.

**Brand promise:** "Where nikah begins with deen."

**Three pillars every feature must serve:**
1. **Seriousness** — intent to marry is enforced, not assumed
2. **Deen-authenticity** — religious practice is declared, structured, and visible
3. **Haya (modesty) by design** — privacy defaults, guarded communication, Wali involvement

**Anti-goals (product personality):** No endless swiping. No gamified streaks. No "likes you" vanity mechanics. No dating-app visual language.

---

## 2. Personas

**P1 — The Seeker (primary user)**
Practicing Muslim, 22–38, wants nikah within 6–24 months. Frustrated by Muzz/Salams: too many non-serious profiles, ghosting, people "just looking." Willing to fill a longer application if it filters out time-wasters. Values privacy (especially sisters — photo control is critical).

**P2 — The Wali / Guardian (secondary user)**
Father, brother, uncle, or appointed guardian of a female seeker. May be low-tech. Wants oversight without micromanaging: who is she talking to, what stage is it at. Needs a lightweight, dignified experience — not a full app commitment.

**P3 — The Parent-Assisted Seeker**
Seeker whose family drives the search. Profile may be co-managed. (P2 scope — design for it, don't build it in v1.)

---

## 3. Core Product Concept — How Ikhlas Works

The user journey in one paragraph:

> Download → **Apply** (not "sign up") → pass the **Eligibility Gate** (intent declaration + screening questionnaire + verification) → build a **Deen-first profile** → receive **curated daily matches** (limited, quality over quantity) → express interest → on mutual interest, a **guarded conversation** opens (time-boxed, purpose-driven, optional Wali visibility) → progress to **Family Stage** (wali contact exchange / meeting intent) → mark outcome (proceeding offline / not a match) → exit the pool when married, alhamdulillah.

The app is a funnel toward offline nikah, not an engagement loop. Success = users *leaving* because they got married.

---

## 4. Detailed Workflows

### 4.1 Onboarding & The Eligibility Gate (P0 — the product IS this)

**Step 0 — Landing**
- App opens with brand moment: gold "i" monogram, "Where nikah begins with deen."
- Copy frames it as an *application*: "Ikhlas is for Muslims serious about nikah. Membership is by application."
- CTA: **"Begin my application"** (not "Sign up")

**Step 1 — Account creation**
- **Login: Google Sign-In or Email OTP** (both native to Firebase; add Sign in with Apple for the iOS build). Phone OTP login → Phase 2, behind the same auth interface.
- **Phone number: mandatory to collect in Phase 1** — required field, format-validated (Indian mobile), stored *unverified* (`phoneVerified=false`). OTP verification switches on in Phase 2. Needed for Wali invites + abuse/ban keying.
- One account per person (Firebase account-linking by email across methods).
- *Why email/Google now, not SMS: avoids India DLT registration on the launch critical path. The gate — selfie liveness + review — is the real abuse moat, not the phone credential.*

**Step 2 — Intent Declaration (the gate's front door)**
- Full-screen, reverent moment. User must actively affirm:
  - "I am seeking nikah, and I intend to marry within a reasonable timeframe."
  - "I am not currently married." → **Ruling (July 2026): polygamy is excluded from Ikhlas at all stages — no married applicants, no disclosure path, no future flag.** Married status hard-rejects.
  - "I understand Ikhlas is not for casual chatting or friendship."
- Checkbox affirmations + typed name as signature. Timestamp stored.
- Copy makes accountability spiritual, not legal: "Ikhlas means sincerity. This declaration is between you and Allah — and it is the standard we hold every member to."

**Step 3 — Screening Questionnaire (~12–15 questions, 4–6 min)**
Structured, not free-text-heavy. Sections:

*A. Readiness*
- Target nikah timeframe: within 6 months / 6–12 / 12–24 / exploring (→ **"exploring" is soft-rejected**: "Ikhlas may not be right for you yet — join our list for when you're ready." This is the gate doing its job.)
- Financially/personally prepared to marry? (self-declared, scaled)
- Have you spoken to your family about marriage? (yes / will involve them / prefer not to say)

*B. Deen profile*
- Prayer: 5 daily consistently / most / working on it / rarely → **Gate (Ab's ruling, July 2026): "5 daily consistently" passes automatically. "Most" routes to manual review** (honest people who occasionally miss a prayer will pick "most" — auto-rejecting it selects for box-tickers over truth-tellers; reviewer judges via short answers). "Working on it" and "rarely" soft-reject.
- Sect/madhhab (optional display), hijab/beard practice, Quran relationship, halal income & riba-avoidance stance (the halal-finance standard)

*C. Basics*
- DOB (18+ enforced), gender, marital status (never married / divorced / widowed), children, ethnicity, languages, country + city, willing to relocate, education, profession
- Revert status (optional, celebrated not flagged)

*D. Short answers (2 required, 150 chars min each)*
- "Why are you seeking nikah now?"
- "Describe your relationship with your deen."
- These are the human-review signal for seriousness.

*E. Creed & Finance Affirmations (hard-gate — "Do not affirm" soft-rejects)*
- **E1 Tawhid:** "I affirm that all worship and supplication is for Allah alone. I do not invoke, supplicate to, or seek help from the deceased, saints, or graves." → Affirm / Do not affirm
  - *Wording note (fiqh-accuracy, non-negotiable): the question targets istighatha (invoking the deceased), NOT grave visitation itself, which is established sunnah (Sahih Muslim 976). Never publish wording that implies visiting graves is shirk.*
- **E2 Riba belief:** "I affirm that riba (interest) is impermissible, including conventional interest-based home, car, and personal loans and credit-card interest." → Affirm / Do not affirm
  - Targets riba specifically; does not gate on scholar-approved Islamic finance structures (murabaha, ijara).
- **E3 Riba practice:** current situation → (a) no interest-based debt (b) legacy debt, actively exiting (c) using interest-based financing and intend to continue
  - (c) soft-rejects. (b) passes with an **honest-disclosure badge** shown to matches — transparency before nikah, and it rewards honesty instead of selecting for box-tickers.
- *Positioning note: Section E functions as an aqeedah gate and leans the pool Salafi/Athari. Accepted trade: sharper wedge, smaller market. This supersedes the softer stance in Open Question #7 for creed items; sect/madhhab display remains optional and non-gated.*

**Step 4 — Verification (P0)**
- **Selfie liveness check** — mandatory for every applicant, matched against profile photos, never shown to other users (Muzz-pattern; this is the anti-catfishing gate)
- Phone number collected at Step 1 (stored, unverified in Phase 1; OTP verification in Phase 2)
- **Aadhaar (DigiLocker) — optional, NOT a gate.** Opting in grants a verified trust badge + boosts match ranking, and returns verified DOB + gender. Positioned as status/reassurance, not entry friction. (P1 to build; selfie-only at launch is acceptable.)

**Step 5 — Review & Decision (AI-Assisted, three-tier funnel)**
- **Tier 1 — Deterministic gate (~60%):** structured answers (age, married, timeframe, prayer, E1–E3) auto-decide clear passes and clear rejects in milliseconds.
- **Tier 2 — AI triage (~40% → shrinks to ~14% for humans):** an LLM reads the two short answers + structured context, outputs a recommendation + confidence + flags. High-confidence clear passes → approved; junk/gibberish/contradictions → soft-rejected. **AI may auto-approve and auto-reject junk, but NEVER auto-rejects on faith-sincerity — ambiguous sincerity always escalates to a human.**
- **Tier 3 — Human (Ab/moderator):** reviews only the escalated ambiguous middle via the admin dashboard. Target decision < 24h.
- **Users are never told AI was involved.** The decision is Ikhlas's; "reviewed by our team" stays true because a human is in the loop on every non-obvious case.
- **Audit:** every AI recommendation and every human override is logged — the bias check (catches systematic down-scoring of reverts / less-fluent English).
- Outcomes: **Approved** → welcome + profile completion · **Soft rejection** → dignified waitlist message (never shame) · **Needs info** → one clarification round.
- The 24h wait is a *feature*: signals exclusivity, kills impulse signups. (See `ikhlas-tech-requirements.md` for the Cloud Function architecture.)

**Step 6 — Profile completion**
- Photos: min 1, max 6. **Privacy default: photos hidden** — user chooses visibility mode (see §4.3)
- Guided bio prompts (no blank text box): "My ideal first year of marriage looks like…", "Deen practice I'm most consistent in…", "What I'm looking for in a spouse…"
- Preferences: age range, location radius / countries, sect flexibility, marital-status openness, children openness, relocation
- **Wali setup (sisters — strongly encouraged; brothers — optional):** add Wali name, relationship, phone → Wali receives SMS/WhatsApp intro link (see §4.5)

**Acceptance criteria (gate):**
- [ ] Section E "Do not affirm" answers (E1, E2) and E3(c) cannot proceed to the pool
- [ ] E3(b) users carry the honest-disclosure badge on their profile
- [ ] No user can view any profile before approval
- [ ] "Exploring" timeframe answer cannot proceed to the pool
- [ ] Intent declaration timestamp + answers immutable and auditable
- [ ] Selfie verification required before approval
- [ ] Rejection copy is warm and leaves a door open
- [ ] Under-18 DOB hard-blocks with no retry loophole

---

### 4.2 Discovery & Matching (P0)

**Model: Curated daily batch — NOT swiping.**
- Each user receives **5 matches per day** at a fixed time (after Fajr window, e.g. 7am local — on-brand).
- Each match is a full profile card: deen profile front and center, photos per privacy rules, compatibility highlights ("You both pray 5 daily · Both open to relocating · Same madhhab").
- Actions per match: **Express Interest** (with optional note, 200 chars) / **Pass** (optional private reason — feeds algorithm) / **Save for tomorrow** (1 slot).
- No public "who liked you" grid in v1 (P1 consideration — it drifts toward vanity mechanics).

**Matching logic (v1 — deterministic, no ML):**
1. Hard filters first (mutual): gender, age ranges, location/relocation compatibility, marital-status openness, children openness
2. Scoring: deen-practice alignment (weighted heaviest), timeframe alignment, sect/madhhab preference, language, education, ethnicity preference (allowed, common in this market)
3. Freshness/fairness: new + recently active profiles boosted; nobody buried

**Search (P1):** filtered browse for paid tier only, capped results/day. v1 ships batch-only — scarcity is the point.

**Acceptance criteria:**
- [ ] Daily batch of exactly 5 (or fewer if pool is small — show "Quality over quantity" empty-state, never filler profiles)
- [ ] Passed profiles don't reappear for 90 days
- [ ] Both users' hard filters respected bidirectionally
- [ ] Inactive >30 days profiles removed from circulation (pool hygiene)

---

### 4.3 Photo Privacy (P0 — table stakes, execute flawlessly)

Three modes, chosen per-user, changeable anytime:
1. **Visible** — photos shown to daily matches
2. **Blurred until match** — silhouette/blur; auto-reveals on mutual interest
3. **Private (request-only)** — hidden even after matching; user grants reveal per-conversation, revocable

Plus:
- Screenshot deterrence: FLAG_SECURE on Android; iOS screenshot detection → warning logged, repeat = flag to moderation
- Photos watermarked with viewer's user ID (light, diagonal) — leak tracing
- No photo downloads, no long-press save

**Acceptance criteria:**
- [ ] Default for all new users = Blurred until match
- [ ] Reveal grant is per-conversation and revocable; revoke re-blurs immediately
- [ ] Watermark present on every rendered photo

---

### 4.4 Communication — Guarded Conversations (P0)

**Opening a conversation:**
- Mutual interest → conversation unlocks with a **bismillah moment**: both parties see etiquette guidelines (adab screen) before first message. One-time acknowledgment.
- If a Wali is linked with "observe" permission, both parties see a badge: **"This conversation is visible to [her] Wali."** Transparency builds trust and self-regulates behavior.

**Structure (anti-ghosting, purpose-driven):**
- **Stage 1 — Introduction (days 1–14):** text only. Guided question prompts available in-chat ("Ask about: family expectations · deen practice · finances · children · living situation"). No photo sharing in chat, no external links, no phone numbers (regex + ML filter blocks and warns).
- **Stage 2 — Deepening (unlocked by mutual opt-in):** voice notes enabled; supervised video call (P1) — in-app, optionally with Wali as third participant.
- **Stage 3 — Family Stage:** either party taps **"Involve families"** → structured exchange: Wali contact details shared through the app (not typed in chat), meeting-intent recorded. This is the app's success event.

**Conversation lifecycle rules:**
- **14-day activity rule:** no messages for 7 days → both nudged; 14 days → conversation auto-archives with respectful closure notice. Kills zombie chats and ghosting limbo.
- **Concurrent conversation cap: 3 active.** Serious seekers, not collectors. (Differentiator — no competitor does this.)
- **Graceful exit:** "End with dua" button → sends a respectful pre-written closure ("JazakAllah khair for your time — I don't feel we're a match. May Allah grant you a righteous spouse.") No silent ghosting; ending a chat requires either this or explicit block.
- Unmatched/ended conversations: content retained 90 days for moderation, then purged.

**Acceptance criteria:**
- [ ] Contact-info sharing blocked pre–Family Stage (phone/email/social handle patterns)
- [ ] 3-conversation cap enforced; must close one to open another
- [ ] Auto-archive at 14 days inactivity with notice to both
- [ ] "End with dua" flow — no conversation can be abandoned silently while active
- [ ] Wali-visible badge accurate at all times

---

### 4.5 Wali / Guardian Flow (P0 for sisters, optional for brothers)

**Design principle:** Wali experience is a **lightweight web portal via magic link** — no app install, no account password. (Low-tech fathers must succeed on the first try.)

**Flow:**
1. Seeker adds Wali (name, relationship, phone) during profile setup or later
2. Wali gets SMS/WhatsApp: "[Name] has invited you to be her Wali on Ikhlas, an app for Muslims seeking nikah. Tap to see how it works." → branded, dignified explainer page → OTP verify → portal
3. **Wali portal shows:** her active conversations (names + stage only, or full transcripts — *she* chooses the permission level), Family Stage requests, and a "Request pause" action (flags concern to the seeker, does not hard-block in v1)
4. **Permission levels (set by the seeker):** Notified only (stage changes) / Observer (read conversations) / Gatekeeper (P1: approves matches before chat opens)
5. Wali is notified at: new mutual match, Stage 2 request, Family Stage initiation

**Acceptance criteria:**
- [ ] Wali onboarding completable in <2 minutes on mobile web
- [ ] Seeker controls permission level and can change/remove Wali anytime (with Wali notified — no silent removal, integrity matters)
- [ ] Wali never sees other users' daily match batches — only conversations involving his ward

---

### 4.6 Trust, Safety & Moderation (P0)

- **Report reasons:** not serious about marriage / already married undisclosed / inappropriate content / asking to move off-app / fake profile / harassment. Report → auto-freeze conversation → moderator review < 24h.
- **Block:** instant, mutual invisibility forever.
- **Three-strike system:** warning → 7-day suspension → permanent ban (device + phone-number banned).
- **"Not serious" reports are first-class:** 2 independent "not serious" reports → account re-review (re-affirm intent declaration or exit). This operationalizes the eligibility gate post-entry.
- **Content filters:** profanity, contact-info, harassment patterns — Cloud Function on message write.
- **Admin dashboard (P0, internal web app):** application review queue, report queue, user search, ban tools, conversation viewer (with audit log of moderator access — privacy accountability).

---

### 4.7 Lifecycle & Exit

- **Success exit:** "We're proceeding to nikah" flow → both confirm → accounts paused with celebration moment + optional testimonial request (marketing gold). Reactivation possible if it doesn't proceed.
- **Pause mode:** hide from pool without deleting (Ramadan, exams, istikhara period — culturally aware pause reasons in the UI).
- **Deletion:** full data deletion within 30 days, GDPR-style, self-serve.

---

## 5. Requirements Summary

### P0 — Cannot launch without
| # | Requirement |
|---|---|
| 1 | Google + Email OTP login; phone collected (mandatory, unverified P1); one account per person; 18+ enforcement |
| 2 | Eligibility gate: intent declaration + questionnaire + soft rejection |
| 3 | Selfie liveness verification (mandatory) |
| 4 | AI-Assisted Review (three-tier funnel) + admin dashboard with AI-recommendation display + override log |
| 5 | Deen-first profile with guided prompts |
| 6 | Daily batch matching (5/day, hard filters + scoring) |
| 7 | Photo privacy: 3 modes, blur default, watermarking, screenshot deterrence |
| 8 | Guarded chat: adab screen, contact-info blocking, 3-chat cap, 14-day rule, End-with-dua |
| 9 | Wali web portal (magic link) with permission levels |
| 10 | Report/block/strike moderation system |
| 11 | Family Stage flow with structured Wali contact exchange |
| 12 | Push notifications (match batch, messages, stage changes) |
| 13 | Pause / success-exit / delete flows |

### P1 — Fast follows (first 90 days)
- In-app supervised video calls (with Wali third-participant option)
- Filtered search for premium tier
- Aadhaar (DigiLocker) optional trust badge — boosts match ranking, grants verified age/gender (Muzz-pattern)
- Wali "Gatekeeper" permission level
- Voice-note bios
- Compatibility questionnaire v2 (values deep-dive, displayed as alignment %)
- Arabic + Urdu localization (English-first at launch)

### P2 — Future (design for, don't build)
- Parent-managed profiles (P3 persona)
- Matchmaker/imam partner accounts (community endorsement layer)
- Islamic pre-marriage course integration (post–Family Stage upsell)
- ML-based matching
- Mahr/istikhara educational content hub

---

## 6. Monetization

- **Founding members (waitlist):** lifetime discount honored — this promise is already public, it's contractual in spirit.
- **Model: paid membership, no free tier for browsing.** A price is itself a seriousness filter and funds manual review. Free users can apply + see blurred previews of match count only.
- **Suggested v1 pricing (INR, India Phase 1):** validate against Shaadi/Jeevansathi/Muzz India before committing. Indicative: Monthly ~₹599 / Quarterly ~₹1,299 / Founding lifetime per waitlist promise. India WTP is real (Shaadi/Jeevansathi charge to contact) but at Indian price points, not AED-equivalents.
- **Sisters pricing question** → Open Questions §10.
- No pay-per-contact, no coin systems, no boosts — those are dating-app mechanics and off-brand.

---

## 7. Success Metrics

**North star: Family Stage initiations per 100 active members per month.** (Proxy for marriages — measurable in-app.)

Leading (weekly):
- Application → approval rate (target 60–75%; if >90% the gate is too soft)
- Approval → completed profile: >85%
- Daily batch open rate: >60%
- Mutual match → first message within 48h: >70%
- Ghost rate (conversations ended by timeout vs. End-with-dua): <30% timeout

Lagging (monthly/quarterly):
- Family Stage initiations (north star)
- Reported "not serious" rate: <2% of active users (gate integrity metric)
- Success exits (self-reported nikah proceedings)
- M3 retention of *unmatched* users: >40% (are serious users staying while searching?)
- Sister:brother ratio between 40:60 and 60:40 (marketplace health — most competitors are ~70% male; the gate + wali features are the sister-acquisition weapon)

---

## 8. Technical Architecture (recommended, decisive)

**Stack: Flutter + Firebase (asia-south1, Mumbai).** Fastest path to launch for a solo builder; you already work in this ecosystem. Backend choice locked after evaluating Supabase — Firebase wins on your fluency + document-shaped launch work; matching-query weakness is deferred and solved later with an isolated query layer, not a re-platform. (See `ikhlas-tech-stack.md`.)

- **Auth:** Firebase — Google Sign-In + Email OTP (Apple on iOS); phone OTP → Phase 2, behind one auth interface. Phone number collected mandatorily in Phase 1, stored unverified.
- **DB:** Cloud Firestore — collections: `users`, `applications`, `matches` (daily batch docs), `conversations`, `messages` (subcollection), `walis`, `reports`, `strikes`
- **Functions (Cloud Functions):** daily batch generation (scheduled, per-timezone), message content filter (onWrite), application auto-scoring, stage-transition logic, 14-day archiver (scheduled), notification fan-out
- **Storage:** Firebase Storage — photos served **only** via short-lived signed URLs through a resizing/watermarking function; originals never exposed
- **Verification (India Phase 1):** Selfie liveness via a passive-liveness SDK (Yoti/AWS Rekognition Liveness/HyperVerge). Optional Aadhaar trust badge via DigiLocker aggregator (Surepass / Cashfree / Setu / Sandbox) — this also returns verified DOB + gender for opted-in users. Do NOT integrate UIDAI directly; the aggregator holds the AUA/KUA licence.
- **Push:** FCM
- **Wali portal:** simple Flutter Web or plain HTML/JS on Netlify hitting Cloud Functions (you know this stack from the landing page)
- **Admin dashboard:** Flutter Web, moderator-role gated
- **Analytics:** Firebase Analytics + Mixpanel for funnel events
- **Security rules:** users can never query the `users` collection directly — all discovery flows through server-generated `matches` docs. This single rule enforces the entire "no browsing" model at the data layer.

**Key data-model decision:** a `stage` field on `conversations` (`intro` → `deepening` → `family` → `closed_dua` / `closed_timeout` / `success`) drives permissions, Wali notifications, and the north-star metric. Model it as an auditable event log, not just a mutable field.

---

## 9. Phased Delivery Plan

**Phase 1 — Foundation (weeks 1–4):** Auth, eligibility gate flow, application review admin, profile builder, verification SDK integration
**Phase 2 — Core loop (weeks 5–8):** batch matching engine, photo privacy system, guarded chat with all rules
**Phase 3 — Differentiators (weeks 9–11):** Wali portal, Family Stage, moderation tooling, notifications
**Phase 4 — Launch prep (weeks 12–14):** pricing/paywall, founding-member redemption from waitlist sheet, App Store/Play review (matrimonial apps get extra scrutiny — prepare content-moderation documentation), closed beta with 50 waitlist members (25/25 gender-balanced), fix, launch.

**Beta gate to public launch:** ≥1 Family Stage initiation and <5% "not serious" reports in beta.

---

## 10. Open Questions (need Ab's ruling)

1. **Prayer-consistency cutoff** — *RESOLVED (July 2026)*: "5 daily consistently" auto-passes; "most" → manual review; "working on it"/"rarely" soft-reject.
2. **Polygamy** — *RESOLVED (July 2026)*: excluded at all stages. Married applicants hard-reject at the intent declaration.
3. **Sisters' pricing:** free or discounted for sisters to fix ratio (common industry tactic), or equal pricing as a statement of seriousness both ways? Recommendation: equal price, but sisters get priority application review — signals respect, not desperation marketing.
4. **Divorced/widowed with children:** fully in v1 pool? Recommendation: yes — underserved by competitors and deeply sunnah-aligned; strong content angle.
5. **Launch geography** — *RESOLVED (July 2026)*: **India, Phase 1.** Firebase asia-south1, DigiLocker/Aadhaar rail, INR pricing, India-native vendors (HyperVerge, MSG91, Razorpay). GCC/diaspora revisited post-India.
6. **Manual review capacity** — *largely resolved by AI-Assisted Review*: three-tier funnel keeps Ab's human load to the escalated ~14% (~65 min/day even at 3,000 applications/month). Moderator-hire trigger deferred; revisit if escalation volume sustains high.
7. **Sect handling** *(partially resolved)*: Section E creed affirmations now function as an aqeedah gate (Ab's ruling, July 2026). Sect/madhhab *label* remains optional display + optional preference filter — the gate is on creed affirmations, not sect self-identification.

---

## 11. What This Doc Does NOT Cover (separate workstreams)
- Marketing/launch campaign plan (Instagram → waitlist → founding cohort)
- Detailed UI design system (extends existing brand: Fraunces, gold-as-illumination, girih patterns)
- Legal: Terms, Privacy Policy, India DPDP Act compliance + data-residency (asia-south1), App Store/Play matrimonial-category compliance, individual-PAN DLT registration (for Phase 2 SMS)
- Get Quran app (separate product, separate spec)


# Ikhlas — Technical Requirements & Phase 1 Build Plan (India)

**Stack:** Flutter + Firebase · **Region:** asia-south1 (Mumbai) · **Launch:** India Phase 1

Companion to `ikhlas-prd-v1.md`. Scope: Auth → Eligibility Gate (deterministic + AI triage) → Verification → Application Review Admin → Profile Builder. Matching and chat are Phase 2.

---

## 0. Authentication Model (Phase 1 — LOCKED)

**Login (identity):** Google Sign-In + Email OTP, both native to Firebase, behind one `AuthProvider` interface.
- Add **Sign in with Apple** for the iOS build (App Store requires it when Google login is offered).
- Enable Firebase **account-linking by email** so one person = one account across methods.
- **Phone OTP is Phase 2**, added as a third implementation behind the same interface — no rewrite.

**Phone number (profile fact, decoupled from login):**
- **MANDATORY to collect in Phase 1** — required field in the application flow; no completed application without it. Format-validated (Indian mobile pattern).
- **Stored unverified** at launch (`phoneVerified=false`); OTP verification switches on in Phase 2 as a straight upgrade on data already held.
- Needed regardless of login for: **Wali invites**, **abuse/ban keying**, and the Phase-2 verification upgrade.

**Why this is safe:** an unverified phone raises the cost of throwaway/re-entry accounts, but the real abuse moat is the gate (selfie liveness + manual review), not the phone field. Login stays frictionless (Google one-tap); the number is captured one screen into the application.

**Why email OTP over SMS at launch:** avoids India DLT registration on the critical path (the one unavoidable SMS paperwork step), zero per-message cost, works today. SMS/WhatsApp OTP + Wali-invite SMS come in Phase 2 once DLT (individual PAN) is registered.

## Firestore Schema (v1)

```
users/{uid}
  status: "applying" | "under_review" | "approved" | "soft_rejected" | "suspended" | "banned" | "paused" | "success_exit"
  authProvider: "google" | "email_otp"           // phone_otp added Phase 2, same interface
  email                                           // from Google/email login (verified)
  phone, phoneVerified (bool)                     // Phase 1: MANDATORY to collect, phoneVerified=false (OTP verify = Phase 2)
  createdAt, lastActiveAt
  gender: "male" | "female"
  dob (Timestamp — 18+ validated server-side)
  profile: {
    displayName, city, country, willingToRelocate,
    ethnicity, languages[], education, profession,
    maritalStatus: "never_married" | "divorced" | "widowed",
    hasChildren, revert (bool, optional),
    sect (optional), madhhab (optional),
    bioPrompts: [{promptId, answer}],
    ribaDisclosureBadge (bool — from E3(b)),
    aadhaarBadge (bool — optional verified trust badge; boosts match ranking)
  }
  photoPrivacy: "visible" | "blur_until_match" | "request_only"   // default blur_until_match
  photos: [{storagePath, order}]                                   // paths only; never public URLs
  preferences: { ageMin, ageMax, countries[], acceptDivorced, acceptWidowed, acceptChildren, relocationRequired, sectPreference? }
  wali: { name, relationship, phone, permissionLevel: "notify"|"observe", verified } | null
  strikes: int

applications/{uid}                    // immutable after decision — audit trail
  submittedAt, decidedAt, decidedBy ("auto" | moderatorUid)
  intentDeclaration: { affirmations[], typedName, timestamp }      // never editable
  answers: {
    timeframe: "6m"|"6_12m"|"12_24m"|"exploring",
    prayer: "five_daily"|"most"|"working"|"rarely",
    financiallyReady, familyAware,
    e1_tawhid: "affirm"|"not_affirm",
    e2_riba: "affirm"|"not_affirm",
    e3_ribaPractice: "none"|"exiting"|"continuing",
    shortAnswers: { whyNow, deenRelationship }
  }
  autoScore: { result: "auto_pass"|"auto_reject"|"manual_review", reasons[] }
  aiTriage: {                                     // AI-Assisted Review layer
    recommendation: "approve"|"reject"|"escalate",
    confidence: 0.0-1.0,
    flags: [],                    // e.g. ["gibberish","contradicts_structured","low_sincerity_signal"]
    model, runAt
  }                               // AI NEVER final judge on sincerity; "escalate" -> human queue
  verification: {
    selfie: { provider, checkId, livenessResult, reviewedAt },              // MANDATORY gate
    aadhaar: { provider, verified, dobVerified, genderVerified } | null     // OPTIONAL trust badge
  }
  decision: "approved"|"soft_rejected"|"needs_info"
  moderatorNotes (moderator-only subfield)

moderators/{uid}
  role: "reviewer" | "admin"

config/gateRules                      // tunable without app release
  autoRejectAnswers: { timeframe: ["exploring"], prayer: ["working","rarely"], e1:["not_affirm"], e2:["not_affirm"], e3:["continuing"] }
  manualReviewAnswers: { prayer: ["most"] }
```

**Immutability rule:** `applications/{uid}` becomes write-locked (except `moderatorNotes`, `decision*` fields via admin) the moment it's submitted. The intent declaration is legal/spiritual audit trail — it must never be editable by anyone, including admins.

## 2. Security Rules — the three laws

1. **No browsing at the data layer:** clients may `get` only their own `users/{uid}`. No client can ever `list`/`query` the `users` collection. (Phase 2 discovery reads server-generated `matches/{uid}/daily/{date}` docs only.)
2. **Gate state is server-authoritative:** `status` is writable only by Cloud Functions/admin. A client cannot self-approve.
3. **Photos never public:** Storage rules deny all direct reads; photos served exclusively through the signed-URL + watermark function (Phase 2 builds the watermarker; Phase 1 stores originals private).

## 3. Cloud Functions (Phase 1 set)

**The three-tier review funnel** (this is the core of the gate — see PRD "AI-Assisted Review"):
`onApplicationSubmit` runs deterministic rules → decides ~60%. The undecided ~40% go to `aiTriageApplication` → auto-approves clear passes + auto-rejects junk → only the ambiguous ~14% land in the human queue. **AI may auto-approve and auto-reject junk/gibberish, but may NEVER auto-reject on faith-sincerity grounds — ambiguous sincerity always escalates to a human.**

| Function | Trigger | Job |
|---|---|---|
| `onApplicationSubmit` | Firestore onCreate `applications/{uid}` | Validate 18+ + married=hard-reject; run `config/gateRules` (creed E1–E3, timeframe, prayer). Deterministic pass/reject, else → hand to AI triage |
| `aiTriageApplication` | Called by onApplicationSubmit (or Firestore onWrite) | LLM reads the 2 short answers + structured context → writes `aiTriage{recommendation,confidence,flags}`. High-conf approve → approve. Junk/gibberish → soft-reject. Else → human queue. Logs recommendation for audit |
| `onVerificationWebhook` | HTTPS (selfie-liveness provider webhook) | Attach liveness result; gate requires liveness PASS before any approval fires |
| `onAadhaarVerify` | Callable (optional, user-initiated) | DigiLocker aggregator flow → set `aadhaarBadge`, verified DOB/gender. Never blocks approval |
| `approveApplication` / `rejectApplication` | Callable (moderator-gated) | Human decision on escalated cases. Set decision, flip `users.status`, notify, lock application doc, log override-vs-AI |
| `sendWaliInvite` | Callable | SMS/WhatsApp magic link (Indian SMS provider) — one-time token → Wali OTP web page |
| `notifyDecision` | Firestore onUpdate | FCM push + templated copy (approved / soft_rejected / needs_info — PRD tone). **Never reveals AI involvement** |

**Audit requirement:** every `aiTriage` recommendation and every human override is retained. This is your bias check — if AI systematically down-scores reverts or less-fluent English, the override log surfaces it.

## 4. Flutter App — Phase 1 Screens

1. **Splash / brand moment** (monogram, tagline)
2. **"Begin my application"** landing
3. **Login** — Google Sign-In + Email OTP (one screen with both options)
3a. **Phone number capture** (mandatory, format-validated, stored unverified — collected right after login, before/at start of application)
4. **Intent Declaration** (full-screen, typed-name signature)
5. **Questionnaire** — sections A–E as a stepped flow with progress indicator (~8 screens; one question-group per screen, Fraunces headers, gold accents)
6. **Short answers** (2 screens, 150-char minimum enforced)
7. **Selfie verification** (SDK-embedded screen — mandatory)
8. **Aadhaar trust badge (optional)** — skippable DigiLocker flow; "Add a verified badge" framing, never a wall
8. **"Application under review"** waiting state (this screen carries the exclusivity feel — design it properly, not a spinner)
9. **Decision screens**: approved welcome / soft-rejection (warm, waitlist CTA) / needs-info
10. **Profile builder**: photos + privacy mode picker, bio prompts, preferences, Wali setup
11. **Settings stub**: pause, delete account, edit profile

State management: Riverpod. Routing: go_router with `status`-based redirect guards (an "applying" user can never deep-link past the gate).

## 5. Admin Dashboard (Flutter Web, moderator-gated)

Phase 1 needs only:
- **Review queue**: escalated (human-needed) applications, oldest first — shows answers, short answers, liveness result, **the AI recommendation + confidence + flags** (as a suggestion, not a decision), one-click approve / soft-reject / needs-info + notes
- **AI override log**: every case where you disagreed with AI triage — your bias-monitoring surface
- **User search** by phone/uid
- **Gate rules editor** (edits `config/gateRules` — tune cutoffs without an app release)

## 6. Vendor decisions needed before Week 1 code

1. **Selfie liveness (mandatory gate):** HyperVerge (India-native, strong local coverage) vs. AWS Rekognition Liveness (cheap, in-AWS) vs. Yoti. **Recommend HyperVerge** for India Phase 1. Confirm → I spec the SDK + webhook.
2. **Aadhaar / DigiLocker (optional badge):** Surepass vs. Cashfree vs. Setu vs. Sandbox — aggregator holds the AUA/KUA licence (you do NOT integrate UIDAI directly). Recommend **Surepass or Cashfree**. Only needed when you build the optional badge (can slip to P1).
3. **SMS provider (Phase 2 — OTP verification + Wali invites):** MSG91 (does SMS + WhatsApp, DLT-compliant). **Not launch-critical** — email/Google auth ships Phase 1 without it. Start individual-PAN DLT registration in parallel so it's ready for Phase 2.
4. **AI triage model:** a Haiku-class model via the Anthropic API — cheap (~₹0.29/triaged application), fast, strong instruction-following for the rubric. Confirm and I'll write the triage prompt + function.
5. **Firebase region:** `asia-south1` (Mumbai) — confirmed for India latency + data residency.

## Regulatory / compliance notes (India)
- **DLT registration** required for transactional SMS (via the SMS provider) before OTP/Wali messages send.
- **Aadhaar handling:** never store raw Aadhaar numbers; store only the verified-badge boolean + verified DOB/gender returned by the aggregator. Aadhaar-optional keeps you off the heaviest compliance burden at launch.
- **DPDP Act (India data protection):** self-serve deletion + consent already in the PRD lifecycle — keep it.
- **App Store / Play matrimonial category:** prepare content-moderation documentation; matrimonial + UGC apps get extra review scrutiny.

## 7. Week-by-week

- **W1:** Firebase project (asia-south1) + security rules + Google/email-OTP auth (behind AuthProvider interface) + mandatory phone capture + intent declaration + questionnaire UI
- **W2:** Deterministic gate engine (`onApplicationSubmit` + `config/gateRules`) + short answers + waiting/decision screens
- **W3:** AI triage function (`aiTriageApplication` + rubric prompt) + selfie-liveness SDK + webhook + admin review queue (with AI-recommendation display)
- **W4:** Profile builder + optional Aadhaar badge flow + Wali invite + settings + end-to-end test with 15 dummy applications covering every path (deterministic reject, AI auto-approve, AI junk-reject, human-escalate, liveness fail)

**Exit criteria for Phase 1:** a real phone can apply; get correctly gated on every deterministic rule (5-daily, E1–E3, "exploring", under-18, married); ambiguous short answers route through AI triage and escalate to the admin queue when uncertain; a moderator decision flips status and notifies — all with zero ability to see another user, and with no user ever told AI was involved.

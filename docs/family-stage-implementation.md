# Family Stage, disclosures & Wali digest — implementation notes

Covers the conversation → disclosures → Wali digest → Family Stage
contact-exchange flow. This is the **most safety-sensitive surface in the
app**: it is where a chaperoned, on-platform conversation gives way to
guardian contact exchange and an off-platform hand-off. It ships **locked
behind a CA / legal sign-off flag** and runs only among known testers until
that sign-off (PRD §5 P0 #11, §7 legal).

## 1. Conversation opens on mutual interest
Unchanged behaviour (`onEntryAction`): mutual `interested` → a guarded
conversation opens, subject to the 3-active-conversation cap (PRD §4.4).

## 2. Disclosures unlock at conversation open
Income band, residency status and nationality are collected at the gate but
are **deliberately withheld from the match card** and never used to rank
(PRD §0). They unlock to the other party the moment a mutual conversation
opens, stored on the conversation as `disclosures.<uid>` and surfaced in the
in-chat profile sheet under a **DISCLOSURES** section.

## 3. Periodic Wali digest — symmetric rule, conditional delivery
`sendWaliDigests` (scheduled, 09:00 IST) walks open conversations and, per
each conversation's own cadence (`waliDigest.cadenceDays`, default 3), sends
the **new conversation activity** to each partner's guardian.

- **Symmetric:** both partners are evaluated identically every run.
- **Conditional:** a guardian receives the digest only if that partner keeps
  a Wali at **`observe`** permission (PRD §4.5 — "full transcripts … *she*
  chooses the permission level"). Re-computed live each run, so a permission
  change takes effect immediately.
- Every digest is written to `waliDigests/*` for a durable audit trail
  (moderator-readable — privacy accountability, PRD §4.6).
- **Delivery is over WhatsApp** (Meta Cloud API, `whatsapp.js`). A digest is
  *business-initiated*, so Meta requires an **approved template** and its
  variables can't hold multi-line text — so WhatsApp carries a **notification**
  (ward name + new-message count), and the **full transcript stays in
  `waliDigests/*`** for the wali portal (PRD §4.5 magic-link surface). Delivery
  is **inert until provisioned** (`WHATSAPP_TOKEN` secret +
  `config/whatsapp.phoneNumberId`), falling back to an audit-only log;
  `deliverWaliDigest` is the single integration point.

### WhatsApp provisioning (one-time, outside this repo)
1. WhatsApp Business Account + verified Meta Business.
2. A sender phone number → its `PHONE_NUMBER_ID`.
3. A permanent access token → `firebase functions:secrets:set WHATSAPP_TOKEN`.
4. An approved template (default name `wali_digest`) with a two-variable BODY,
   e.g. *"As-salamu alaykum {{1}}. There is new activity in the Ikhlaas
   conversation you oversee — {{2}} new message(s). Please review it together,
   insha’Allah."*
5. `config/whatsapp = { phoneNumberId, templateName?, languageCode? }`.

> Meta's template rule is a hard constraint, not a preference: you cannot push a
> free-form transcript to a guardian over WhatsApp. If the transcript itself
> must reach guardians, build the wali portal (magic link → `waliDigests`) or add
> a guardian-email channel — both are follow-ups.

## 4. "Involve families" → accept / decline
- Either party taps **Involve families** → `requestFamilyStage` records the
  request and notifies the other party.
- The other party **accepts** (`confirmFamilyStage`) or **declines**
  (`declineFamilyStage`):
  - **Accept** → `stage = family`, structured guardian-contact exchange
    (`familyExchange`), north-star metric event, and an **off-platform
    threshold notice** posted to the conversation (chaperoned in-app contact
    steps back here).
  - **Decline** → clears the pending request, posts a gentle system note, and
    notifies the initiator. The conversation continues; either party may ask
    again later (a new request supersedes the decline).

## 5. Schema (on the conversation doc)
```
conversations/{convId} {
  ...existing (participants, stage, profiles, ...)
  disclosuresUnlocked: true,
  disclosures: { <uid>: { incomeBand, residencyStatus, nationality } },
  waliDigest: {
    enabled: true,
    cadenceDays: 3,
    lastSentAt: <ts|null>,
    lastDeliveredAt: <ts>,        // set only when a guardian was eligible
  },
  familyStage: {
    requestedBy, requestedAt,     // cleared on decline / confirm
    declined, declinedBy, declinedAt,
    confirmed, confirmedBy, confirmedAt,
    offPlatformNoticeAt,
  },
  familyExchange: { <uid>: { name, relationship, phone } },   // WALI contacts
}

waliDigests/{id} {              // audit trail, moderator-readable
  convId, wardUid, waliName, waliPhone,
  channel: 'whatsapp', messageCount, transcript,
  delivered, providerId, error, at,
}
```

## 6. CA / legal sign-off gate
```
config/featureFlags {
  familyStage: {
    legalSignedOff: false,       // set true ONLY after CA + legal review
    signedOffBy: null, signedOffAt: null,
    testerUids: [ ... ],         // closed-testing allowlist
  }
}
```
`requestFamilyStage`, `confirmFamilyStage` and `sendWaliDigests` all check
`familyStageAllowed(participants)`: permitted iff `legalSignedOff === true`
**or** every participant is in `testerUids`. **Absent/malformed doc → fully
locked** (the safe default is "nobody", never "everybody"). `declineFamilyStage`
is intentionally ungated — it only clears an already-pending request.

**To enable closed testing:** set `config/featureFlags.familyStage.testerUids`
to the tester UIDs. **To go GA:** after CA + legal review, set
`legalSignedOff: true` (record `signedOffBy` / `signedOffAt`).

## ⚠️ Flagged divergence — contact sharing scope
The implementation task prompt asked to share the **couple's personal phone
numbers** at the family-involvement step. The PRD is explicit and consistent
that the Family Stage exchanges the couple's **Wali (guardian) contact
details** — not the couple's own numbers (PRD §4.4 Stage 3, §5 P0 #11, §1
overview). Per the task's own instruction ("If the PRD and this prompt ever
diverge on that, follow the PRD and flag it"), **this implementation shares
Wali contacts only.** The hand-off then continues off-platform between the two
guardians. If sharing personal numbers is ever wanted, it must come back
through CA / legal sign-off — not a silent code change.

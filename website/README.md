# Ikhlaas — Landing / Waitlist Site

Static pre-launch landing page for Ikhlaas (`ikhlaas.io`). Single self-contained
`index.html` — no build step. Open it in a browser or serve the folder statically.

## Copy principles (from the copy deck)

- **Lead with the wedge** — the application gate and selectivity, not the table-stakes
  features (Wali / privacy), which are demoted to reassurance in "Built the right way".
- **Concrete facts over adjectives** — "fewer than 4 in 10 accepted", "selfie liveness",
  "reviewed by a person".
- **Truthful numbers** — the ~1,000 figure is framed as *following / waiting*, never
  "members" (this is a pre-launch waitlist, not accepted members).

## Editing the following count

The following/waitlist number lives in a single editable value in the inline script:

```js
const FOLLOWING_COUNT = "1,000";
```

It fills every `.js-following` span on the page. Update it as the following grows —
keep it truthful.

## Before launch

- Verify the Ar-Rum 21 ayah diacritics with a knowledgeable person (see copy deck).
- Wire the waitlist form to a real endpoint (see the `TODO` in the submit handler).
- Point the "Sign in" and footer links to real destinations.

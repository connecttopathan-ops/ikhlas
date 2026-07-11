/// Questionnaire answer model — mirrors `applications/{uid}.answers` and the
/// `users/{uid}` profile fields in ikhlas-tech-requirements.md (v1.2).
/// Staged locally across the stepped flow; written once at submission
/// (the application doc is immutable after that — enforced by rules).
///
/// Data principle (PRD §0): collect for disclosure, rank on deen + intent.
/// Section F (deenDetail) and the C-section facts are PROFILE data — they are
/// written to `users/{uid}.profile`, never to the immutable application doc.
class QuestionnaireAnswers {
  // ---- A. Readiness ----
  String? timeframe; // 6m | 6_12m | 12_24m | exploring
  String? financiallyReady; // ready | preparing | not_yet
  String? familyAware; // yes | will_involve | prefer_not

  // ---- B. Deen profile ----
  String? prayer; // five_daily | most | working | rarely
  String sect = ''; // optional display
  String madhhab = ''; // optional display

  // ---- C. Basics ----
  String? gender; // male | female
  DateTime? dob;
  String? maritalStatus; // never_married | divorced | widowed
  bool? hasChildren;
  bool revert = false; // optional, celebrated not flagged
  int? heightCm; // 140–210
  // Location — three questions, NO "livingAbroad" flag (PRD §0/§4.1).
  String country = 'India'; // where I live NOW
  String city = '';
  String countryOfOrigin = 'India'; // where I'm FROM (distinct for diaspora)
  String? residencyStatus; // citizen | permanent_resident | long_term_visa | work_visa | student_visa
  bool? willingToRelocate;
  String languages = ''; // comma-separated in UI → list on submit
  String ethnicity = ''; // optional
  String? education; // enum (was free text)
  String? profession; // enum (was free text)
  String? incomeBand; // COLLECTED, never shown, never scored (PRD §0)
  String? familyType; // joint | nuclear
  String? familyReligiosity; // very_practising | practising | moderate | cultural
  String healthDisclosure = ''; // optional; revealed at conversation stage

  // ---- D. Short answers ----
  String whyNow = '';
  String deenRelationship = '';

  // ---- E. Creed & finance affirmations ----
  String? e1Tawhid; // affirm | not_affirm
  String? e2Riba; // affirm | not_affirm
  String? e3RibaPractice; // none | exiting | continuing
  String? e4IncomeSource; // halal | uncertain | not_halal

  // ---- F. Deen Detail (NON-GATING — matching signal only, → profile) ----
  String? quran; // hafiz | regular | learning | seeking
  String? islamicStudy; // formal | structured_self | casual | none
  String? fastingBeyondRamadan; // regularly | sometimes | no

  static const int shortAnswerMin = 100;

  bool get sectionAComplete =>
      timeframe != null && financiallyReady != null && familyAware != null;
  bool get sectionBComplete => prayer != null;
  bool get sectionC1Complete =>
      gender != null &&
      dob != null &&
      heightCm != null &&
      maritalStatus != null &&
      // Children only required for divorced/widowed; never-married is auto-false.
      (maritalStatus == 'never_married' || hasChildren != null);
  bool get sectionC2Complete =>
      country.trim().isNotEmpty &&
      city.trim().isNotEmpty &&
      countryOfOrigin.trim().isNotEmpty &&
      residencyStatus != null &&
      willingToRelocate != null &&
      languages.trim().isNotEmpty;
  bool get sectionC3Complete =>
      education != null && profession != null && incomeBand != null;
  bool get sectionC4Complete =>
      familyType != null && familyReligiosity != null; // health optional
  bool get sectionD1Complete => whyNow.trim().length >= shortAnswerMin;
  bool get sectionD2Complete => deenRelationship.trim().length >= shortAnswerMin;
  bool get sectionEComplete =>
      e1Tawhid != null &&
      e2Riba != null &&
      e3RibaPractice != null &&
      e4IncomeSource != null;
  bool get sectionFComplete =>
      quran != null && islamicStudy != null && fastingBeyondRamadan != null;

  List<String> get languagesList => languages
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// Payload for `applications/{uid}.answers` — field names match the schema
  /// exactly (the gate engine and gateRules key off them). Section F is
  /// deliberately absent: it is profile data, never application data.
  Map<String, dynamic> toAnswersMap() => {
        'timeframe': timeframe,
        'financiallyReady': financiallyReady,
        'familyAware': familyAware,
        'prayer': prayer,
        'e1_tawhid': e1Tawhid,
        'e2_riba': e2Riba,
        'e3_ribaPractice': e3RibaPractice,
        'e4_incomeSource': e4IncomeSource,
        'shortAnswers': {
          'whyNow': whyNow.trim(),
          'deenRelationship': deenRelationship.trim(),
        },
      };

  /// Section F → `users/{uid}.profile.deenDetail`. Non-gating; the only
  /// inputs that vary across the approved pool, so the deen weight has
  /// something to bite on (PRD §4.1 Section F — the deen-variance collapse).
  Map<String, dynamic> get deenDetailMap => {
        'quran': quran,
        'islamicStudy': islamicStudy,
        'fastingBeyondRamadan': fastingBeyondRamadan,
      };
}

/// One selectable choice in an option list.
class Choice {
  final String value;
  final String label;
  final String? note; // small muted line under the label
  const Choice(this.value, this.label, {this.note});
}

class Choices {
  static const timeframe = [
    Choice('6m', 'Within 6 months'),
    Choice('6_12m', '6–12 months'),
    Choice('12_24m', '12–24 months'),
    Choice('exploring', 'Just exploring for now'),
  ];
  static const financiallyReady = [
    Choice('ready', 'Yes, I am prepared'),
    Choice('preparing', 'Actively preparing'),
    Choice('not_yet', 'Not yet'),
  ];
  static const familyAware = [
    Choice('yes', 'Yes, they are involved'),
    Choice('will_involve', 'I will involve them'),
    Choice('prefer_not', 'Prefer not to say'),
  ];
  static const prayer = [
    Choice('five_daily', 'Five daily, consistently'),
    Choice('most', 'Most prayers'),
    Choice('working', 'Working on it'),
    Choice('rarely', 'Rarely'),
  ];
  static const gender = [
    Choice('male', 'Brother'),
    Choice('female', 'Sister'),
  ];
  static const maritalStatus = [
    Choice('never_married', 'Never married'),
    Choice('divorced', 'Divorced'),
    Choice('widowed', 'Widowed'),
  ];
  static const yesNo = [
    Choice('yes', 'Yes'),
    Choice('no', 'No'),
  ];
  static const residencyStatus = [
    Choice('citizen', 'Citizen'),
    Choice('permanent_resident', 'Permanent resident'),
    Choice('long_term_visa', 'Long-term visa'),
    Choice('work_visa', 'Work visa'),
    Choice('student_visa', 'Student visa'),
  ];
  static const education = [
    Choice('high_school', 'High school'),
    Choice('diploma', 'Diploma'),
    Choice('bachelors', "Bachelor's degree"),
    Choice('masters', "Master's degree"),
    Choice('doctorate', 'Doctorate (PhD)'),
    Choice('islamic_studies', 'Islamic studies (ʿalim / ʿalimah)'),
    Choice('other', 'Other'),
  ];
  static const profession = [
    Choice('student', 'Student'),
    Choice('healthcare', 'Healthcare / Medicine'),
    Choice('engineering_it', 'Engineering / IT'),
    Choice('business', 'Business / Self-employed'),
    Choice('education', 'Education / Academia'),
    Choice('government', 'Government / Public sector'),
    Choice('finance', 'Finance / Accounting'),
    Choice('legal', 'Legal'),
    Choice('trade', 'Skilled trade'),
    Choice('homemaker', 'Homemaker'),
    Choice('other', 'Other'),
  ];
  // INR annual. COLLECTED for disclosure at Family Stage, never scored (§0).
  static const incomeBand = [
    Choice('under_3l', 'Under ₹3 lakh'),
    Choice('r3_6l', '₹3–6 lakh'),
    Choice('r6_12l', '₹6–12 lakh'),
    Choice('r12_24l', '₹12–24 lakh'),
    Choice('r24_50l', '₹24–50 lakh'),
    Choice('r50l_plus', '₹50 lakh and above'),
    Choice('prefer_not', 'Prefer not to say'),
  ];
  static const familyType = [
    Choice('joint', 'Joint family'),
    Choice('nuclear', 'Nuclear family'),
  ];
  static const familyReligiosity = [
    Choice('very_practising', 'Very practising'),
    Choice('practising', 'Practising'),
    Choice('moderate', 'Moderate'),
    Choice('cultural', 'Cultural / nominal'),
  ];
  static const e1 = [
    Choice('affirm', 'I affirm'),
    Choice('not_affirm', 'I do not affirm'),
  ];
  static const e3 = [
    Choice('none', 'I have no interest-based debt'),
    Choice('exiting', 'I have legacy debt and am actively exiting it',
        note: 'Shown to matches as an honest-disclosure badge — '
            'transparency before nikah.'),
    Choice('continuing',
        'I use interest-based financing and intend to continue'),
  ];
  static const e4 = [
    Choice('halal', 'Yes — from a source I consider halal'),
    Choice('uncertain', 'Uncertain'),
    Choice('not_halal', 'No'),
  ];
  // ---- Profile builder preferences (PRD v1.2 §4.1) ----
  // The member's OWN financial stance — scored as ALIGNMENT, never a floor.
  static const financialExpectation = [
    Choice('comfortable_provision', 'Comfortable provision'),
    Choice('modest_is_fine', 'A modest life is enough'),
    Choice('build_together', "We'll build together"),
  ];
  static const spouseWork = [
    Choice('works', 'Works / will work'),
    Choice('prefer_not', "I'd prefer they don't"),
    Choice('no_preference', 'No preference'),
  ];
  // Deen preference — what you WANT, so matching can score the gap (P1).
  static const deenPrefPrayer = [
    Choice('five_daily', 'Prays five daily'),
    Choice('most_ok', 'Five daily or most is fine'),
    Choice('no_preference', 'No preference'),
  ];
  static const deenPrefHijabBeard = [
    Choice('required', 'Required'),
    Choice('preferred', 'Preferred'),
    Choice('no_preference', 'No preference'),
  ];
  static const deenPrefRiba = [
    Choice('debt_free', 'Free of interest-based debt'),
    Choice('exiting_ok', 'Exiting legacy debt is fine'),
    Choice('no_preference', 'No preference'),
  ];

  // ---- Section F (non-gating) ----
  static const quran = [
    Choice('hafiz', 'Hafiz'),
    Choice('regular', 'I read regularly'),
    Choice('learning', 'Learning to read'),
    Choice('seeking', 'Seeking to start'),
  ];
  static const islamicStudy = [
    Choice('formal', 'Formal (madrasa / ʿalim course)'),
    Choice('structured_self', 'Structured self-study'),
    Choice('casual', 'Casual'),
    Choice('none', 'None yet'),
  ];
  static const fasting = [
    Choice('regularly', 'Regularly (e.g. Mondays & Thursdays)'),
    Choice('sometimes', 'Sometimes'),
    Choice('no', 'Not beyond Ramadan currently'),
  ];
}

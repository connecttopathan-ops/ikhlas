/// Questionnaire answer model — mirrors `applications/{uid}.answers` and the
/// `users/{uid}` profile fields in ikhlas-tech-requirements.md.
/// Staged locally across the stepped flow; written once at submission
/// (the application doc is immutable after that — enforced by rules).
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
  String country = 'India';
  String city = '';
  bool? willingToRelocate;
  String languages = ''; // comma-separated in UI → list on submit
  String ethnicity = ''; // optional
  String education = '';
  String profession = '';

  // ---- D. Short answers (150 chars min each) ----
  String whyNow = '';
  String deenRelationship = '';

  // ---- E. Creed & finance affirmations ----
  String? e1Tawhid; // affirm | not_affirm
  String? e2Riba; // affirm | not_affirm
  String? e3RibaPractice; // none | exiting | continuing

  static const int shortAnswerMin = 150;

  bool get sectionAComplete =>
      timeframe != null && financiallyReady != null && familyAware != null;
  bool get sectionBComplete => prayer != null;
  bool get sectionC1Complete =>
      gender != null && dob != null && maritalStatus != null && hasChildren != null;
  bool get sectionC2Complete =>
      country.trim().isNotEmpty &&
      city.trim().isNotEmpty &&
      willingToRelocate != null &&
      languages.trim().isNotEmpty;
  bool get sectionC3Complete =>
      education.trim().isNotEmpty && profession.trim().isNotEmpty;
  bool get sectionD1Complete => whyNow.trim().length >= shortAnswerMin;
  bool get sectionD2Complete => deenRelationship.trim().length >= shortAnswerMin;
  bool get sectionEComplete =>
      e1Tawhid != null && e2Riba != null && e3RibaPractice != null;

  List<String> get languagesList => languages
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// Payload for `applications/{uid}.answers` — field names match the schema
  /// exactly (the gate engine and gateRules key off them).
  Map<String, dynamic> toAnswersMap() => {
        'timeframe': timeframe,
        'financiallyReady': financiallyReady,
        'familyAware': familyAware,
        'prayer': prayer,
        'e1_tawhid': e1Tawhid,
        'e2_riba': e2Riba,
        'e3_ribaPractice': e3RibaPractice,
        'shortAnswers': {
          'whyNow': whyNow.trim(),
          'deenRelationship': deenRelationship.trim(),
        },
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
}

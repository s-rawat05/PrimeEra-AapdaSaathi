/// Understanding a spoken SAFE / HELP reply — pure functions, no hardware, fully unit-tested.
///
/// Safety rules:
/// * HELP always wins: "help", "not safe", "surakshit nahi" … are HELP even if "safe" also appears.
/// * Anything unclear is [VoiceIntent.unknown] — silence or noise is NEVER treated as SAFE.
/// * SAFE is only sent after a separate spoken YES (see VoiceResponder).
library;

enum VoiceIntent { safe, help, yes, no, unknown }

// Every word list is matched as WHOLE WORDS in both scripts. Substring matching is unsafe:
// "कहाँ" (where) contains "हाँ" (yes) and would wrongly confirm SAFE.
const _helpWords = {
  'help',
  'helpme',
  'sos',
  'emergency',
  'madad',
  'madat',
  'bachao',
  'bachaao',
  'bacha',
  'unsafe',
  'danger',
};
const _helpDevanagari = ['मदद', 'बचाओ', 'बचा', 'हेल्प', 'खतरा'];
const _safeWords = {'safe', 'fine', 'surakshit', 'surakshith', 'theek', 'thik', 'thick', 'okay'};
const _safeDevanagari = ['सुरक्षित', 'ठीक', 'सेफ'];
const _negations = {'not', 'no', 'nahi', 'nahin', 'nai', 'isnt', 'arent', 'dont'};
const _negationsDevanagari = ['नहीं', 'नही', 'ना'];
const _yesWords = {'yes', 'yeah', 'yep', 'haan', 'han', 'haa', 'ha', 'ji', 'confirm', 'correct', 'sahi', 'right'};
const _yesDevanagari = ['हाँ', 'हां', 'सही', 'यस', 'जी'];
const _noWords = {'no', 'nope', 'nahi', 'nahin', 'nai', 'cancel', 'galat', 'wrong'};
const _noDevanagari = ['नहीं', 'नही', 'गलत', 'नो'];

// Latin letters and Devanagari letters/marks, excluding the danda punctuation (U+0964/0965).
final _word = RegExp(r'[a-zऀ-ॣ०-ॿ]+');

List<String> _words(String t) => _word.allMatches(t.toLowerCase()).map((m) => m.group(0)!).toList();

bool _any(List<String> words, Set<String> latin, List<String> deva) =>
    words.any((w) => latin.contains(w) || deva.contains(w));

/// Answer to "Are you safe?": SAFE, HELP or unknown.
VoiceIntent interpretAnswer(String? transcript) {
  final t = (transcript ?? '').trim();
  if (t.isEmpty) return VoiceIntent.unknown;
  final words = _words(t);
  if (_any(words, _helpWords, _helpDevanagari)) return VoiceIntent.help;
  final saysSafe = _any(words, _safeWords, _safeDevanagari);
  final negated = _any(words, _negations, _negationsDevanagari);
  if (saysSafe && negated) return VoiceIntent.help; // "not safe", "surakshit nahi", "ठीक नहीं"
  if (saysSafe) return VoiceIntent.safe;
  return VoiceIntent.unknown;
}

/// Answer to "You said safe — say YES to confirm": YES, NO, HELP or unknown.
VoiceIntent interpretConfirmation(String? transcript) {
  final t = (transcript ?? '').trim();
  if (t.isEmpty) return VoiceIntent.unknown;
  final words = _words(t);
  if (_any(words, _helpWords, _helpDevanagari)) return VoiceIntent.help;
  final yes = _any(words, _yesWords, _yesDevanagari);
  final no = _any(words, _noWords, _noDevanagari);
  if (yes && !no) return VoiceIntent.yes;
  if (no && !yes) return VoiceIntent.no;
  return VoiceIntent.unknown; // both or neither → ask again rather than guess
}

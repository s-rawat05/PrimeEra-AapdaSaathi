/// Typed UI strings in English and Hindi. Switching language rebuilds the tree instantly.
///
/// Official alert text from the server is never translated here — it is shown verbatim.
class Strings {
  const Strings(this.lang);

  final String lang;

  static const supported = ['en', 'hi'];

  bool get isHi => lang == 'hi';
  String _p(String en, String hi) => isHi ? hi : en;

  /// BCP-47 tag used for text-to-speech.
  String get ttsLocale => isHi ? 'hi-IN' : 'en-IN';

  // ---------------------------------------------------------------- general
  String get appName => _p('AapdaSaathi', 'आपदा साथी');
  String get tagline => _p('App where possible. SMS everywhere. A human for those who don\'t reply.',
      'जहाँ संभव हो ऐप। हर जगह SMS। जो जवाब न दें, उनके लिए एक इंसान।');
  String get ok => _p('OK', 'ठीक है');
  String get cancel => _p('Cancel', 'रद्द करें');
  String get confirm => _p('Confirm', 'पुष्टि करें');
  String get back => _p('Back', 'वापस');
  String get next => _p('Next', 'आगे');
  String get skip => _p('Skip', 'छोड़ें');
  String get save => _p('Save', 'सहेजें');
  String get retry => _p('Try again', 'फिर कोशिश करें');
  String get close => _p('Close', 'बंद करें');
  String get done => _p('Done', 'हो गया');
  String get refresh => _p('Refresh', 'ताज़ा करें');
  String get loading => _p('Loading…', 'लोड हो रहा है…');
  String get optionalNote => _p('Note (optional)', 'टिप्पणी (वैकल्पिक)');
  String get requiredNote => _p('Note (required)', 'टिप्पणी (ज़रूरी)');
  String get demo => _p('DEMO', 'डेमो');
  String get estimate => _p('ESTIMATE', 'अनुमान');
  String get unknown => _p('Unknown', 'अज्ञात');
  String get call112 => _p('Call 112 (emergency)', '112 पर कॉल करें (आपातकाल)');
  String errorPrefix(String m) => _p('Something went wrong: $m', 'कुछ गलत हुआ: $m');
  String get couldNotOpen => _p('Could not open the app on this device.', 'इस डिवाइस पर ऐप नहीं खुल सका।');

  // ---------------------------------------------------------------- connectivity
  String get online => _p('Online', 'ऑनलाइन');
  String get offline => _p('Offline — showing last saved information', 'ऑफ़लाइन — पिछली सहेजी जानकारी दिख रही है');
  String get reconnecting => _p('Reconnecting…', 'फिर से जुड़ रहे हैं…');
  String lastSync(String t) => _p('Last synced $t', 'आख़िरी सिंक $t');
  String get neverSynced => _p('Not synced yet', 'अभी सिंक नहीं हुआ');
  String queuedCount(int n) =>
      _p('$n reply queued — not yet delivered', '$n जवाब कतार में — अभी पहुँचा नहीं');
  String get queuedNotDelivered => _p('Queued — not yet delivered', 'कतार में — अभी पहुँचा नहीं');
  String get queuedExplain => _p(
      'Your reply is saved on this phone and will be sent automatically when the connection returns. '
          'It has NOT reached the control room yet. If you can, also reply by SMS.',
      'आपका जवाब इस फ़ोन पर सहेजा गया है और कनेक्शन लौटने पर अपने-आप भेजा जाएगा। '
          'यह अभी नियंत्रण कक्ष तक नहीं पहुँचा है। हो सके तो SMS से भी जवाब दें।');
  String queueFailed(String m) => _p('A queued reply could not be delivered: $m', 'कतार का जवाब नहीं पहुँच सका: $m');
  String get cachedData => _p('Saved copy — may be out of date', 'सहेजी हुई प्रति — पुरानी हो सकती है');

  // ---------------------------------------------------------------- splash / intro
  String get introTitle1 => _p('Official alerts, made clear', 'आधिकारिक चेतावनी, साफ़ शब्दों में');
  String get introBody1 => _p(
      'Get official disaster alerts for your ward in a form that works for you: flashing, vibration, voice or easy-read.',
      'अपने वार्ड की आधिकारिक आपदा चेतावनी अपने अनुकूल रूप में पाएँ: चमकती स्क्रीन, कंपन, आवाज़ या आसान भाषा।');
  String get introTitle2 => _p('One tap: SAFE or HELP', 'एक टैप: सुरक्षित या मदद');
  String get introBody2 => _p(
      'Tell the control room you are safe, or ask for help. No internet? Reply 1 or 2 by SMS.',
      'नियंत्रण कक्ष को बताइए कि आप सुरक्षित हैं, या मदद माँगिए। इंटरनेट नहीं? SMS से 1 या 2 भेजें।');
  String get introTitle3 => _p('Someone will check on you', 'कोई आपकी ख़बर लेगा');
  String get introBody3 => _p(
      'If you do not reply, a neighbour, caregiver or verified volunteer is asked to check on you.',
      'अगर आप जवाब नहीं देते, तो पड़ोसी, देखभालकर्ता या सत्यापित स्वयंसेवक से आपकी जाँच करने को कहा जाता है।');
  String get getStarted => _p('Get started', 'शुरू करें');

  // ---------------------------------------------------------------- login
  String get signIn => _p('Sign in', 'साइन इन करें');
  String get phoneNumber => _p('Mobile number', 'मोबाइल नंबर');
  String get phoneHint => _p('+91 98XXXXXXXX', '+91 98XXXXXXXX');
  String get sendCode => _p('Send code by SMS', 'SMS से कोड भेजें');
  String get enterCode => _p('6-digit code', '6 अंकों का कोड');
  String get verify => _p('Verify and continue', 'सत्यापित करें और आगे बढ़ें');
  String get yourName => _p('Your full name (first sign-up only)', 'आपका पूरा नाम (केवल पहली बार)');
  String get changeNumber => _p('Change number', 'नंबर बदलें');
  String get invalidPhone => _p('Enter a valid mobile number (8–20 digits).', 'सही मोबाइल नंबर डालें (8–20 अंक)।');
  String get invalidCode => _p('Enter the 6-digit code.', '6 अंकों का कोड डालें।');
  String get nameRequired => _p('This number is new. Please enter your name.', 'यह नंबर नया है। कृपया अपना नाम डालें।');
  String get demoPersonas => _p('Demo personas', 'डेमो पात्र');
  String get demoPersonasHint => _p(
      'Fictional accounts for the drill. Tap one to sign in without an SMS code.',
      'अभ्यास के लिए काल्पनिक खाते। बिना SMS कोड साइन इन करने के लिए किसी एक को टैप करें।');
  String get demoOtpHint => _p(
      'Demo mode: the SMS code appears in the command centre\'s SMS simulator, not on a real phone.',
      'डेमो मोड: SMS कोड कमांड सेंटर के SMS सिम्युलेटर में दिखता है, असली फ़ोन पर नहीं।');
  String get supabaseSignIn => _p('Sign in with Supabase phone OTP', 'Supabase फ़ोन OTP से साइन इन करें');
  String roleName(String role) => switch (role) {
        'resident' => _p('Resident', 'निवासी'),
        'caregiver' => _p('Caregiver', 'देखभालकर्ता'),
        'neighbour' => _p('Neighbour', 'पड़ोसी'),
        'volunteer' => _p('Volunteer', 'स्वयंसेवक'),
        'admin' => _p('Admin', 'एडमिन'),
        'operator' => _p('Control room operator', 'नियंत्रण कक्ष ऑपरेटर'),
        _ => role,
      };

  // ---------------------------------------------------------------- onboarding
  String get chooseLanguage => _p('Choose your language', 'अपनी भाषा चुनें');
  String get languageNote => _p('Alerts and the app will use this language. Official alert text is shown as issued.',
      'चेतावनी और ऐप इसी भाषा में होंगे। आधिकारिक चेतावनी का पाठ जैसा जारी हुआ वैसा ही दिखेगा।');
  String get english => 'English';
  String get hindi => 'हिन्दी';
  String get needsTitle => _p('What helps you during an alert?', 'चेतावनी के समय आपको किससे मदद मिलती है?');
  String get needsNote => _p(
      'Tell us what you need, not a diagnosis. You can change this any time in Profile.',
      'हमें अपनी ज़रूरत बताइए, बीमारी नहीं। आप इसे प्रोफ़ाइल में कभी भी बदल सकते हैं।');
  String needLabel(String n) => switch (n) {
        'hearing' => _p('I may not hear an alarm', 'मैं अलार्म नहीं सुन पाता/पाती'),
        'vision' => _p('I need alerts read aloud', 'मुझे चेतावनी पढ़कर सुनानी होगी'),
        'mobility' => _p('I need help to move or evacuate', 'मुझे चलने या निकलने में मदद चाहिए'),
        'bedridden' => _p('I cannot leave my bed without help', 'मैं बिना मदद बिस्तर से नहीं उठ सकता/सकती'),
        'cognitive' => _p('I prefer simple words and pictures', 'मुझे आसान शब्द और चित्र पसंद हैं'),
        'elderly_alone' => _p('I am elderly and live alone', 'मैं बुज़ुर्ग हूँ और अकेले रहता/रहती हूँ'),
        'speech' => _p('I cannot answer by voice', 'मैं आवाज़ से जवाब नहीं दे सकता/सकती'),
        'feature_phone' => _p('I mostly use SMS / a basic phone', 'मैं ज़्यादातर SMS / साधारण फ़ोन इस्तेमाल करता/करती हूँ'),
        _ => n,
      };
  String get livesAlone => _p('I live alone', 'मैं अकेले रहता/रहती हूँ');
  String get hasSmartphone => _p('This is my own smartphone', 'यह मेरा अपना स्मार्टफ़ोन है');
  String get consentTitle => _p('Consent and contacts', 'सहमति और संपर्क');
  String get fullName => _p('Full name', 'पूरा नाम');
  String get ward => _p('Ward', 'वार्ड');
  String get chooseWard => _p('Choose your ward', 'अपना वार्ड चुनें');
  String get consentRegistry => _p(
      'I agree to be on the vulnerable-persons registry so responders can check on me (required, 90 days).',
      'मैं संवेदनशील व्यक्तियों की सूची में शामिल होने के लिए सहमत हूँ ताकि सहायक मेरी जाँच कर सकें (ज़रूरी, 90 दिन)।');
  String get consentLocation => _p(
      'Share my exact home location with responders during an active emergency.',
      'सक्रिय आपातकाल के दौरान मेरे घर की सटीक लोकेशन सहायकों के साथ साझा करें।');
  String get consentCaregiver => _p('Let my trusted contacts see my alert status.',
      'मेरे भरोसेमंद संपर्क मेरी चेतावनी स्थिति देख सकें।');
  String get guardianConsent => _p('A guardian is giving consent for this person', 'इस व्यक्ति की ओर से अभिभावक सहमति दे रहे हैं');
  String get guardianName => _p('Guardian name', 'अभिभावक का नाम');
  String get useMyLocation => _p('Use my current location', 'मेरी वर्तमान लोकेशन लें');
  String get locationCaptured => _p('Location captured', 'लोकेशन ली गई');
  String get locationUnavailable => _p('Location not available — you can skip this.', 'लोकेशन उपलब्ध नहीं — आप इसे छोड़ सकते हैं।');
  String get addressOptional => _p('Address (optional)', 'पता (वैकल्पिक)');
  String get landmarkOptional => _p('Landmark (optional)', 'निशानी (वैकल्पिक)');
  String get trustedContacts => _p('Trusted contacts', 'भरोसेमंद संपर्क');
  String get addContact => _p('Add contact', 'संपर्क जोड़ें');
  String get contactName => _p('Contact name', 'संपर्क का नाम');
  String get contactPhone => _p('Contact phone', 'संपर्क फ़ोन');
  String get contactCanSeeLocation => _p('Can see my location', 'मेरी लोकेशन देख सकते हैं');
  String get register => _p('Register', 'पंजीकरण करें');
  String get registryRequired => _p('Registry consent is required to register.', 'पंजीकरण के लिए सूची सहमति ज़रूरी है।');
  String get registered => _p('You are registered.', 'आपका पंजीकरण हो गया।');

  // ---------------------------------------------------------------- nav
  String get navHome => _p('Home', 'होम');
  String get navEvacuate => _p('Evacuate', 'निकासी');
  String get navAlerts => _p('Alerts', 'चेतावनियाँ');
  String get navProfile => _p('Profile', 'प्रोफ़ाइल');
  String get navPeople => _p('My people', 'मेरे लोग');
  String get navChecks => _p('Checks', 'जाँच');
  String get navTasks => _p('Tasks', 'कार्य');

  // ---------------------------------------------------------------- resident home
  String greeting(String name) => _p('Hello, $name!', 'नमस्ते, $name!');
  String get noActiveAlerts => _p('No active alerts', 'कोई सक्रिय चेतावनी नहीं');
  String get noActiveAlertsBody => _p(
      'There is no official alert for your ward right now. Keep the app installed — we will alert you.',
      'अभी आपके वार्ड के लिए कोई आधिकारिक चेतावनी नहीं है। ऐप रखें — हम आपको सूचित करेंगे।');
  String get officialAlertStatus => _p('Official alert status', 'आधिकारिक चेतावनी स्थिति');
  String get activeAlert => _p('Active alert', 'सक्रिय चेतावनी');
  String get viewAlert => _p('View alert', 'चेतावनी देखें');
  String get respondNow => _p('Respond now', 'अभी जवाब दें');
  String get yourStatus => _p('Your status', 'आपकी स्थिति');
  String get assistance => _p('Assistance', 'सहायता');
  String get sos => 'SOS';
  String get sosLabel => _p('SOS — ask for help', 'SOS — मदद माँगें');
  String get sosSemantics => _p('SOS emergency button. Opens the help request for the active alert.',
      'SOS आपातकालीन बटन। सक्रिय चेतावनी के लिए मदद अनुरोध खोलता है।');
  String get sosNoAlertTitle => _p('No active official alert', 'कोई सक्रिय आधिकारिक चेतावनी नहीं');
  String get sosNoAlertBody => _p(
      'AapdaSaathi sends HELP requests for official alerts only. In any emergency, call 112 now.',
      'आपदा साथी केवल आधिकारिक चेतावनी के लिए मदद अनुरोध भेजता है। किसी भी आपातकाल में अभी 112 पर कॉल करें।');
  String get statAlertsReceived => _p('Alerts received', 'मिली चेतावनियाँ');
  String get statMarkedSafe => _p('Marked safe', 'सुरक्षित दर्ज');
  String get statHelpRequests => _p('Help requests', 'मदद अनुरोध');
  String get registrationInactive => _p('Your registration needs renewal', 'आपके पंजीकरण का नवीनीकरण ज़रूरी है');
  String reverifyDue(String d) => _p('Re-verify consent by $d', '$d तक सहमति फिर से सत्यापित करें');
  String statusName(String s) => switch (s) {
        'SAFE' => _p('Safe', 'सुरक्षित'),
        'HELP' => _p('Help requested', 'मदद माँगी'),
        'NO_REPLY' => _p('Awaiting your reply', 'आपके जवाब की प्रतीक्षा'),
        'PENDING' => _p('Pending', 'लंबित'),
        'UNREACHABLE' => _p('Unreachable', 'संपर्क नहीं हो सका'),
        _ => s,
      };

  // ---------------------------------------------------------------- alert detail
  String get alertTitle => _p('Alert', 'चेतावनी');
  String get officialText => _p('Official alert text', 'आधिकारिक चेतावनी का पाठ');
  String get officialTextNote => _p('Exactly as issued by the authority.', 'जैसा प्राधिकरण ने जारी किया, बिल्कुल वैसा।');
  String get sender => _p('Sender', 'भेजने वाला');
  String get event => _p('Event', 'घटना');
  String get headline => _p('Headline', 'शीर्षक');
  String get description => _p('Description', 'विवरण');
  String get instruction => _p('Instruction', 'निर्देश');
  String get severity => _p('Severity', 'गंभीरता');
  String get urgency => _p('Urgency', 'तात्कालिकता');
  String get certainty => _p('Certainty', 'निश्चितता');
  String get onset => _p('Onset', 'शुरुआत');
  String get expires => _p('Expires', 'समाप्ति');
  String get area => _p('Area', 'क्षेत्र');
  String get source => _p('Source', 'स्रोत');
  String get openOfficialLink => _p('Open official source', 'आधिकारिक स्रोत खोलें');
  String get noInstruction => _p('No instruction was included in the official message.',
      'आधिकारिक संदेश में कोई निर्देश नहीं है।');
  String get readAloud => _p('Read aloud', 'पढ़कर सुनाएँ');
  String get stopAlarm => _p('Stop alarm', 'अलार्म बंद करें');
  String get easyReadSteps => _p('Step by step', 'एक-एक कदम');
  String stepOf(int i, int n) => _p('Step $i of $n', 'कदम $i / $n');
  String get noVoiceNote => _p('You can answer by tapping or by SMS. No voice is needed.',
      'आप टैप करके या SMS से जवाब दे सकते हैं। आवाज़ की ज़रूरत नहीं।');
  String get assistancePrompt => _p('If you need help to move, tap HELP. Someone will be asked to come.',
      'अगर आपको चलने में मदद चाहिए, तो मदद दबाएँ। किसी को आने के लिए कहा जाएगा।');
  String get smsOnlyNote => _p('Your profile says you mostly use SMS. Reply 1 = SAFE or 2 = HELP by SMS.',
      'आपकी प्रोफ़ाइल के अनुसार आप ज़्यादातर SMS इस्तेमाल करते हैं। SMS से 1 = सुरक्षित या 2 = मदद भेजें।');

  // ---------------------------------------------------------------- emergency response
  String get areYouSafe => _p('Are you safe?', 'क्या आप सुरक्षित हैं?');
  String get iAmSafe => _p('I AM SAFE', 'मैं सुरक्षित हूँ');
  String get iNeedHelp => _p('I NEED HELP', 'मुझे मदद चाहिए');
  String get safeSemantics => _p('I am safe. Double tap to tell the control room you are safe.',
      'मैं सुरक्षित हूँ। नियंत्रण कक्ष को बताने के लिए दो बार टैप करें।');
  String get helpSemantics => _p('I need help. Double tap to ask the control room for help.',
      'मुझे मदद चाहिए। नियंत्रण कक्ष से मदद माँगने के लिए दो बार टैप करें।');
  String get confirmSafe => _p('Send "I am safe"?', '"मैं सुरक्षित हूँ" भेजें?');
  String get confirmHelp => _p('Send "I need help"?', '"मुझे मदद चाहिए" भेजें?');
  String get confirmSafeYes => _p('Yes, I am safe', 'हाँ, मैं सुरक्षित हूँ');
  String get confirmHelpYes => _p('Yes, send help', 'हाँ, मदद भेजें');
  String get sending => _p('Sending…', 'भेजा जा रहा है…');
  String get replyBySms => _p('Reply by SMS instead', 'इसके बजाय SMS से जवाब दें');
  String get smsNotGuaranteed => _p(
      'Opens your SMS app with the reply filled in. You must press Send. SMS delivery is not guaranteed.',
      'आपका SMS ऐप जवाब भरकर खुलेगा। आपको भेजें दबाना होगा। SMS पहुँचने की गारंटी नहीं है।');
  String get noSmsGateway => _p('No SMS number is configured in this build. Reply using the number in the alert SMS you received.',
      'इस ऐप में कोई SMS नंबर सेट नहीं है। जो चेतावनी SMS आपको मिला, उसी नंबर पर जवाब दें।');

  // ---------------------------------------------------------------- safe / help
  String get safeConfirmedTitle => _p('You are marked SAFE', 'आप सुरक्षित दर्ज हैं');
  String get safeConfirmedBody => _p(
      'The control room has your reply. Keep following official instructions. If things change, tap HELP.',
      'नियंत्रण कक्ष को आपका जवाब मिल गया है। आधिकारिक निर्देशों का पालन करते रहें। स्थिति बदले तो मदद दबाएँ।');
  String get changedMind => _p('I need help now', 'मुझे अब मदद चाहिए');
  String get helpRequestedTitle => _p('Help requested', 'मदद माँगी गई');
  String get helpRequestedBody => _p('The control room has your request. Stay where it is safe if you can.',
      'नियंत्रण कक्ष को आपका अनुरोध मिल गया है। हो सके तो सुरक्षित जगह पर रहें।');
  String get neighbourAsked => _p('A neighbour has been asked to check on you', 'एक पड़ोसी से आपकी जाँच करने को कहा गया है');
  String get neighbourNotAsked => _p('No neighbour check yet', 'अभी पड़ोसी जाँच नहीं');
  String volunteerStatus(String s) => switch (s) {
        'ASSIGNED' => _p('A volunteer has been assigned', 'एक स्वयंसेवक नियुक्त किया गया है'),
        'ACCEPTED' => _p('A volunteer is on the way', 'एक स्वयंसेवक रास्ते में है'),
        'PENDING_APPROVAL' => _p('Control room is approving a volunteer', 'नियंत्रण कक्ष स्वयंसेवक की मंज़ूरी दे रहा है'),
        _ => _p('Volunteer status: $s', 'स्वयंसेवक स्थिति: $s'),
      };
  String get noVolunteerYet => _p('No volunteer assigned yet', 'अभी कोई स्वयंसेवक नियुक्त नहीं');
  String etaMinutes(String m) => _p('About $m min away (ESTIMATE)', 'लगभग $m मिनट दूर (अनुमान)');
  String get iAmSafeNow => _p('I am safe now', 'अब मैं सुरक्षित हूँ');
  String get backHome => _p('Back to home', 'होम पर वापस');

  // ---------------------------------------------------------------- evacuation
  String get evacuationTitle => _p('Evacuation & relief post', 'निकासी और राहत केंद्र');
  String evacuateTo(String name) => _p('Go to $name', '$name जाएँ');
  String get fromYourLocation => _p('from your location (straight line)', 'आपकी लोकेशन से (सीधी रेखा)');
  String walkEstimate(String m) => _p('About $m min walk — ESTIMATE', 'लगभग $m मिनट पैदल — अनुमान');
  String get directionOnly => _p('Direction only — not a verified safe route', 'केवल दिशा — यह सत्यापित सुरक्षित रास्ता नहीं है');
  String get openInMaps => _p('Open in maps', 'मैप में खोलें');
  String get noReliefPost => _p('No relief post is registered for your ward. Follow official instructions and local authorities.',
      'आपके वार्ड के लिए कोई राहत केंद्र दर्ज नहीं है। आधिकारिक निर्देशों और स्थानीय प्रशासन का पालन करें।');
  String get noAlertForEvacuation => _p('No active alert. Relief posts are shown when an official alert is active.',
      'कोई सक्रिय चेतावनी नहीं। आधिकारिक चेतावनी सक्रिय होने पर राहत केंद्र दिखाए जाते हैं।');
  String get instructions => _p('Instructions', 'निर्देश');
  String get officialInstruction => _p('Official instruction', 'आधिकारिक निर्देश');
  String get aapdaSteps => _p('AapdaSaathi easy-read steps', 'आपदा साथी आसान कदम');
  String get yourPosition => _p('Your position', 'आपकी स्थिति');
  String get reliefPost => _p('Relief post', 'राहत केंद्र');
  String designatedBy(String s) => _p('Designated by: $s', 'नामित: $s');
  String get positionFromDevice => _p('Your position: from this phone\'s GPS', 'आपकी स्थिति: इस फ़ोन के GPS से');
  String get positionFromRegistry => _p('Your position: registered home location', 'आपकी स्थिति: दर्ज घर की लोकेशन');
  String get positionUnknown => _p('Your position is unknown — distance is from your registered area.',
      'आपकी स्थिति अज्ञात है — दूरी आपके दर्ज क्षेत्र से है।');

  // ---------------------------------------------------------------- history
  String get alertHistory => _p('Alert history', 'चेतावनी इतिहास');
  String get noHistory => _p('No alerts yet.', 'अभी कोई चेतावनी नहीं।');
  String repliedVia(String c) => _p('Replied via $c', '$c से जवाब दिया');
  String get incidentClosed => _p('Closed', 'बंद');
  String get incidentActive => _p('Active', 'सक्रिय');

  // ---------------------------------------------------------------- caregiver
  String get caregiverTitle => _p('People you care for', 'जिनकी आप देखभाल करते हैं');
  String get noLinkedResidents => _p('No residents are linked to you yet.', 'अभी आपसे कोई निवासी जुड़ा नहीं है।');
  String get noAlertForPerson => _p('No active alert', 'कोई सक्रिय चेतावनी नहीं');
  String get markSafeOnBehalf => _p('Mark SAFE for them', 'उनके लिए सुरक्षित दर्ज करें');
  String get requestHelpOnBehalf => _p('Request HELP for them', 'उनके लिए मदद माँगें');
  String onBehalfConfirm(String name, String status) =>
      _p('Confirm $status for $name? Add a note on how you know.', '$name के लिए $status की पुष्टि करें? आपको कैसे पता है, टिप्पणी जोड़ें।');
  String get locationShared => _p('Location shared with you', 'आपके साथ साझा लोकेशन');
  String get locationNotShared => _p('Location not shared with you', 'लोकेशन आपके साथ साझा नहीं');
  String get recorded => _p('Recorded.', 'दर्ज हो गया।');

  // ---------------------------------------------------------------- neighbour
  String get checksTitle => _p('Neighbour check requests', 'पड़ोसी जाँच अनुरोध');
  String get noChecks => _p('No check requests right now.', 'अभी कोई जाँच अनुरोध नहीं।');
  String checkOn(String name) => _p('Please check on $name', 'कृपया $name की जाँच करें');
  String get onlyIfSafe => _p('Only go if it is safe for you.', 'केवल तभी जाएँ जब आपके लिए सुरक्षित हो।');
  String get theyAreSafe => _p('They are SAFE', 'वे सुरक्षित हैं');
  String get theyNeedHelp => _p('They need HELP', 'उन्हें मदद चाहिए');
  String get cannotReach => _p('I CANNOT reach them', 'मैं उन तक नहीं पहुँच सकता/सकती');
  String get showClosed => _p('Show closed', 'बंद भी दिखाएँ');
  String outcomeName(String o) => switch (o) {
        // The backend stores neighbour outcomes in lower case (e.g. "cannot_reach").
        'SAFE' || 'safe' => _p('Safe', 'सुरक्षित'),
        'HELP' || 'help' => _p('Needs help', 'मदद चाहिए'),
        'CANNOT_REACH' || 'cannot_reach' => _p('Could not reach', 'नहीं पहुँच सके'),
        'resident_safe' => _p('Resident safe', 'निवासी सुरक्षित'),
        'evacuated' => _p('Evacuated', 'निकाला गया'),
        'needs_rescue' => _p('Needs rescue', 'बचाव चाहिए'),
        'not_found' => _p('Not found', 'नहीं मिले'),
        _ => o,
      };
  String needShort(String n) => switch (n) {
        'hearing' => _p('Hearing', 'सुनना'),
        'vision' => _p('Vision', 'देखना'),
        'mobility' => _p('Mobility', 'चलना-फिरना'),
        'bedridden' => _p('Bedridden', 'बिस्तर पर'),
        'cognitive' => _p('Easy-read', 'आसान भाषा'),
        'elderly_alone' => _p('Elderly, alone', 'बुज़ुर्ग, अकेले'),
        'speech' => _p('Speech', 'बोलना'),
        'feature_phone' => _p('SMS / basic phone', 'SMS / साधारण फ़ोन'),
        _ => n,
      };

  // ---------------------------------------------------------------- volunteer
  String get tasksTitle => _p('Your tasks', 'आपके कार्य');
  String get available => _p('Available for tasks', 'कार्य के लिए उपलब्ध');
  String get availableOn => _p('You can receive new tasks.', 'आपको नए कार्य मिल सकते हैं।');
  String get availableOff => _p('You will not receive new tasks.', 'आपको नए कार्य नहीं मिलेंगे।');
  String get openTasks => _p('Open tasks', 'खुले कार्य');
  String get closedTasks => _p('Closed tasks', 'बंद कार्य');
  String get noOpenTasks => _p('No open tasks.', 'कोई खुला कार्य नहीं।');
  String get noClosedTasks => _p('No closed tasks yet.', 'अभी कोई बंद कार्य नहीं।');
  String get accept => _p('Accept task', 'कार्य स्वीकारें');
  String get cantGo => _p('I can\'t go', 'मैं नहीं जा सकता/सकती');
  String get cantGoTitle => _p('Why can\'t you go?', 'आप क्यों नहीं जा सकते?');
  String get chooseReason => _p('Choose a reason to continue.', 'आगे बढ़ने के लिए कारण चुनें।');
  String reasonName(String r) => switch (r) {
        'route_blocked' => _p('Route blocked', 'रास्ता बंद'),
        'too_far' => _p('Too far', 'बहुत दूर'),
        'unsafe' => _p('Unsafe for me', 'मेरे लिए असुरक्षित'),
        'unavailable' => _p('Not available now', 'अभी उपलब्ध नहीं'),
        _ => r,
      };
  String get taskDetail => _p('Task', 'कार्य');
  String get callResident => _p('Call resident', 'निवासी को कॉल करें');
  String get navigate => _p('Navigate', 'रास्ता देखें');
  String get reachedTitle => _p('I have reached', 'मैं पहुँच गया/गई');
  String get reachedOutcome => _p('What did you find?', 'आपको क्या मिला?');
  String get noteRequiredForOutcome => _p('Add a short note for the control room.', 'नियंत्रण कक्ष के लिए छोटी टिप्पणी जोड़ें।');
  String get submit => _p('Submit', 'जमा करें');
  String get distance => _p('Distance', 'दूरी');
  String get walk => _p('Walk', 'पैदल');
  String taskKind(String k) => switch (k) {
        'neighbour_check' => _p('Neighbour check', 'पड़ोसी जाँच'),
        'volunteer_assist' => _p('Volunteer assistance', 'स्वयंसेवक सहायता'),
        'preevac_assist' => _p('Pre-evacuation assistance', 'निकासी-पूर्व सहायता'),
        _ => k.replaceAll('_', ' '),
      };
  String taskStatusName(String s) => switch (s) {
        'PENDING_APPROVAL' => _p('Awaiting approval', 'मंज़ूरी की प्रतीक्षा'),
        'ASSIGNED' => _p('Assigned to you', 'आपको सौंपा गया'),
        'ACCEPTED' => _p('Accepted — on the way', 'स्वीकृत — रास्ते में'),
        'REACHED' => _p('Reached', 'पहुँच गए'),
        'COMPLETED' => _p('Completed', 'पूरा'),
        'CANT_GO' => _p('Could not go', 'नहीं जा सके'),
        'CANCELLED' => _p('Cancelled', 'रद्द'),
        'REJECTED' => _p('Rejected', 'अस्वीकृत'),
        _ => s,
      };
  String get exactLocation => _p('Exact location', 'सटीक लोकेशन');
  String get residentNeeds => _p('Needs', 'ज़रूरतें');
  String get newTaskTitle => _p('New task assigned', 'नया कार्य सौंपा गया');
  String get newCheckTitle => _p('Neighbour check requested', 'पड़ोसी जाँच का अनुरोध');
  String get notVolunteerProfile => _p('No volunteer profile found for this account.', 'इस खाते के लिए स्वयंसेवक प्रोफ़ाइल नहीं मिली।');

  // ---------------------------------------------------------------- profile
  String get profileTitle => _p('Profile', 'प्रोफ़ाइल');
  String get language => _p('Language', 'भाषा');
  String get myNeeds => _p('My needs', 'मेरी ज़रूरतें');
  String get saveNeeds => _p('Save needs', 'ज़रूरतें सहेजें');
  String get saved => _p('Saved.', 'सहेजा गया।');
  String get permissions => _p('Permissions', 'अनुमतियाँ');
  String get permNotifications => _p('Notifications', 'सूचनाएँ');
  String get permLocation => _p('Location', 'लोकेशन');
  String get permCamera => _p('Camera (for torch blink)', 'कैमरा (टॉर्च चमकाने के लिए)');
  String get permGranted => _p('Allowed', 'अनुमति है');
  String get permDenied => _p('Not allowed', 'अनुमति नहीं');
  String get permPermanentlyDenied => _p('Blocked — open settings', 'अवरुद्ध — सेटिंग्स खोलें');
  String get permRequest => _p('Allow', 'अनुमति दें');
  String get openSettings => _p('Open settings', 'सेटिंग्स खोलें');
  String get permWebNote => _p('Running in a browser: notifications, torch and vibration are limited or unavailable.',
      'ब्राउज़र में चल रहा है: सूचनाएँ, टॉर्च और कंपन सीमित या अनुपलब्ध हैं।');
  String get dndNote => _p(
      'Honest note: Android may not let alarms bypass silent mode or Do Not Disturb. '
          'Keep notifications on and the volume up. SMS alerts are also sent.',
      'सच्ची बात: Android अलार्म को साइलेंट मोड या "परेशान न करें" से आगे नहीं जाने दे सकता। '
          'सूचनाएँ चालू और आवाज़ ऊँची रखें। SMS चेतावनी भी भेजी जाती हैं।');
  String get torchNote => _p('Torch blinking needs a camera flash. Not every phone has one.',
      'टॉर्च चमकाने के लिए कैमरा फ़्लैश चाहिए। हर फ़ोन में नहीं होता।');
  String get consent => _p('Consent', 'सहमति');
  String consentValidUntil(String d) => _p('Registry consent valid until $d', 'सूची सहमति $d तक मान्य');
  String get consentInactive => _p('Registry consent is not active.', 'सूची सहमति सक्रिय नहीं है।');
  String get withdrawConsent => _p('Withdraw consent', 'सहमति वापस लें');
  String get withdrawConfirm => _p(
      'Withdraw consent? You will be removed from the active registry and your exact location will be deleted.',
      'सहमति वापस लें? आपको सक्रिय सूची से हटाया जाएगा और आपकी सटीक लोकेशन मिटा दी जाएगी।');
  String get renewConsent => _p('Renew consent (90 days)', 'सहमति नवीनीकृत करें (90 दिन)');
  String get logout => _p('Sign out', 'साइन आउट');
  String get account => _p('Account', 'खाता');
  String get testAlarm => _p('Test my alert effects', 'मेरे चेतावनी प्रभाव जाँचें');
  String get testAlarmBody => _p('This is a test of AapdaSaathi alert effects on this phone.',
      'यह इस फ़ोन पर आपदा साथी चेतावनी प्रभावों की जाँच है।');
  String get serverLabel => _p('Server', 'सर्वर');

  // ---------------------------------------------------------------- ops / misc
  String get opsTitle => _p('Use the web command centre', 'वेब कमांड सेंटर इस्तेमाल करें');
  String get opsBody => _p(
      'Admin and control-room accounts work in the AapdaSaathi web command centre, not in this app.',
      'एडमिन और नियंत्रण कक्ष खाते आपदा साथी वेब कमांड सेंटर में काम करते हैं, इस ऐप में नहीं।');
  String get unknownRole => _p('This account type is not supported in the app.', 'यह खाता प्रकार ऐप में समर्थित नहीं है।');
  String get newAlertNotification => _p('Official alert — open to respond', 'आधिकारिक चेतावनी — जवाब देने के लिए खोलें');
}

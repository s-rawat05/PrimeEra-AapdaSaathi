-- Production-safe seed: default alert presentation templates only. No people, no wards.
-- Fictional DEMO data is created by the backend (python -m app.demo.seed) and only when
-- DEMO_MODE_ENABLED=true, so a production database never contains demo accounts.
--
-- Templates frame the OFFICIAL text; {headline} must always be present (enforced by a CHECK).

insert into alert_templates (id, hazard_type, language, style, title, body) values
  ('6f2b8a10-0000-4000-8000-000000000001', '*', 'en', 'standard', 'AapdaSaathi: {event} alert',
   E'Official alert from {sender}: {headline}\nInstruction: {instruction}'),
  ('6f2b8a10-0000-4000-8000-000000000002', '*', 'hi', 'standard', 'आपदा साथी: {event} चेतावनी',
   E'{sender} की आधिकारिक चेतावनी: {headline}\nनिर्देश: {instruction}'),
  ('6f2b8a10-0000-4000-8000-000000000003', '*', 'en', 'easy_read', 'Danger: {event}',
   E'There is danger near you: {event}.\nOfficial message: {headline}\nTell us if you are safe.'),
  ('6f2b8a10-0000-4000-8000-000000000004', '*', 'hi', 'easy_read', 'खतरा: {event}',
   E'आपके पास खतरा है: {event}।\nआधिकारिक संदेश: {headline}\nबताइए आप सुरक्षित हैं या नहीं।'),
  ('6f2b8a10-0000-4000-8000-000000000005', '*', 'en', 'sms', 'AapdaSaathi',
   'AapdaSaathi ALERT ({sender}): {headline} Reply 1=SAFE 2=HELP'),
  ('6f2b8a10-0000-4000-8000-000000000006', '*', 'hi', 'sms', 'AapdaSaathi',
   'आपदा साथी चेतावनी ({sender}): {headline} उत्तर दें 1=सुरक्षित 2=मदद')
on conflict (hazard_type, language, style) do nothing;

/**
 * Staging config backup for Seller Studio (rollback).
 * Active config is studio_config.js (production). To revert: copy this over studio_config.js
 * and point background.js / popup.js / manifest host to staging.
 * Anon key is public by design (same as Flutter web). Never use service_role here.
 */
(function (global) {
  global.FLEABER_STUDIO_ENV = {
    label: "staging",
    version: "1.7.27",
    supabaseUrl: "https://fxdknzrqjenzqcvnwqqq.supabase.co",
    /** Hub web canónico (mesma arquitectura HubUrls.liveWebHash). */
    hubWebOrigin: "https://fleaber.pt",
    anonKey:
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ4ZGtuenJxamVuenFjdm53cXFxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3ODA1NTgsImV4cCI6MjA5MjM1NjU1OH0.cmnPjM0YxNbT6RcSurFEnexzLaN6sJsQrjodCz2Wf5I",
  };
})(typeof window !== "undefined" ? window : globalThis);

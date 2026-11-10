/**
 * Production config for Seller Studio Hub reads.
 * Anon key is public by design (same as Flutter web). Never use service_role here.
 * Staging backup: studio_config.staging.js
 */
(function (global) {
  global.FLEABER_STUDIO_ENV = {
    label: "production",
    version: "1.7.29",
    supabaseUrl: "https://bpmpkzwnrbmuqnhgdscf.supabase.co",
    /** Hub web canonico (mesma arquitectura HubUrls.liveWebHash). */
    hubWebOrigin: "https://fleaber.pt",
    anonKey:
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJwbXBrenducmJtdXFuaGdkc2NmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzNjg2NjQsImV4cCI6MjEwNDk0NDY2NH0.8HBa82bp2VboaGA1IAlY5zr5Fl8CdtRgOMj8LJtNF68",
  };
})(typeof window !== "undefined" ? window : globalThis);

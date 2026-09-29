// Thunderbird settings for the information ledger.
//
// Thunderbird runs here purely to keep support@movepeople.ch synced to disk so
// `ir-mail` can read it — the M365 connector has no delegate access to that
// mailbox and Microsoft has disabled basic-auth IMAP, so Thunderbird's built-in
// OAuth is the only door in that needs no admin.
//
// user.js is re-applied at every startup and overrides prefs.js. To undo any of
// this, delete the file and restart Thunderbird.

// THE important one. By default IMAP keeps headers locally and fetches bodies on
// demand — which would leave ir-mail reading subject lines and concluding
// "no reply found" when the answer was sitting in the body. Force full offline
// download so the local store actually contains the mail.
user_pref("mail.server.default.offline_download", true);
user_pref("mail.check_all_imap_folders_for_new", true);

// One file per message instead of one big mbox per folder. Safer to read while
// Thunderbird is writing, and far cheaper to search. Only applies to accounts
// created AFTER this is set, which is why it goes in before the account does.
user_pref("mail.serverDefaultStoreContractID", "@mozilla.org/msgstore/maildirstore;1");

// It lives on a hidden workspace and nobody is watching it: no popups, no sounds,
// no tab restoring, and check for mail often enough that the hourly sweep is
// reading something current.
user_pref("mail.biff.show_alert", false);
user_pref("mail.biff.play_sound", false);
user_pref("mail.server.default.check_time", 5);
user_pref("mail.server.default.check_new_mail", true);
user_pref("mailnews.start_page.enabled", false);

// Never let a background client send anything on its own.
user_pref("mail.warn_on_send_accel_key", true);

// Per-server, not just the default: a folder only gets its offline flag when
// Thunderbird first syncs it, and INBOX is the only one it syncs unprompted.
// Sent matters as much as INBOX here — it is the evidence for "did he reply?".
user_pref("mail.server.server6.offline_download", true);
user_pref("mail.server.server6.autosync_offline_stores", true);
user_pref("mail.server.server6.download_bodies_on_get_new_mail", true);

// Thunderbird shows only IMAP-subscribed folders, and on this account only
// INBOX is subscribed — which silently hid "Sent Items", the evidence for
// whether a reply was actually sent. Ignore subscriptions and take every folder.
user_pref("mail.server.server6.using_subscription", false);

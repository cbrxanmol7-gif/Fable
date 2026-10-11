# Fable backend for Vercel

Fable is a campus introductions and dating site for CU UP. The original repo was a static front-end demo. This version connects its account and social features to Supabase through Vercel Functions.

## What is connected

- CU UP email OTP sign-in (Supabase Auth)
- Profile create/edit and private profile photo upload
- Adult-only profile discovery and compatibility filtering
- Blind introductions with mutual consent, daily cap, and cooldown
- Mutual interest requests and private conversations
- Chat, optional 24-hour messages, date ending, block and report flows
- Moderator report and correction queues (requires explicit moderator role)
- Data export and account deletion
- Privacy settings and server-recorded acceptance of current Terms and Privacy versions

Voice/video calling is not implemented. Live message updates poll the API every few seconds. Report review requires you to designate and staff moderators; no 24-hour response is promised. The in-app Terms and Privacy drafts contain operator/contact placeholders and must be completed and reviewed before collecting real student data. Email OTP is deliberately disabled until configuration is complete.

## Connect this project

1. In Vercel, open project **fable-34iz** and install the **Supabase** integration from Marketplace. Create or connect its Supabase project. Select the same Vercel project when prompted.
2. In Supabase, open **SQL Editor** and run `supabase/migrations/202610110001_fable_backend.sql` once. It creates the schema, access policies, RPCs, and a private photo bucket.
3. In Supabase Auth, set the site URL to `https://fable-34iz.vercel.app` and add that URL plus your local preview URL to the redirect URL allowlist. Configure a custom SMTP sender for arbitrary student email addresses, set email OTP to six digits, and test mail delivery. Supabase's default email sender is not suitable for general student sign-in.
4. In Vercel **Settings → Environment Variables**, add the values below to Preview and Production. Values are available in Supabase **Project Settings → API**. Never add the secret key to browser code or commit it.
5. Replace the operator, support, and privacy-contact placeholders in `Fable.html`. Review the privacy/legal wording and decide data retention and moderation coverage before allowing student sign-up.
6. Add `FABLE_LIVE_ENABLED=true` in Vercel only after SMTP, legal details, and the migration are ready. Redeploy so the function receives the setting.
7. Make a preview deployment and verify the complete flow with test accounts before promoting it. Verify email signup, profile/photo save, discovery, a mutual intro, chat, report, export, and account deletion. Use two verified adult test accounts to exercise matching.

### Environment variables

```env
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
SUPABASE_SECRET_KEY=YOUR_SUPABASE_SECRET_KEY
FABLE_LIVE_ENABLED=false
```

`SUPABASE_PUBLISHABLE_KEY` and `SUPABASE_SECRET_KEY` are the current Supabase key names. The code accepts `SUPABASE_ANON_KEY` as a fallback for the publishable key. Keep the secret key server-only; it is used for private photo storage and account deletion. Do not expose it as a `NEXT_PUBLIC_` value.

## Moderator access

Moderation APIs deny access by default. Grant the `moderator` role only to trusted staff accounts by setting `app_metadata.role` through Supabase's authenticated admin controls. Do not grant it in user-editable `user_metadata`. Test using a separate staff account. The moderator queue includes report context and must be handled as sensitive data.

## Local development

Use Vercel CLI to link the checkout to `fable-34iz`, pull environment variables into the local ignored `.env.local`, then run the Vercel development server. Do not commit `.env.local`. Before `FABLE_LIVE_ENABLED=true`, sign-in requests fail closed.

## Known limits and launch checks

- Supabase Free has plan quotas and may pause inactive projects; verify current plan limits for the expected student load.
- No calls, real-time push delivery, scheduled moderator staffing, or university identity validation beyond a verified `@culkomail.in` email are implemented.
- Email-domain verification proves control of that mailbox, not current enrollment.
- Complete and review legal details and moderation operations before production use, especially because profiles, photos, and dating conversations are sensitive personal data.

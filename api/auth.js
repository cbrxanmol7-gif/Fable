const { send, readBody, supabase } = require('./_lib/http');

module.exports = async (req, res) => {
  try {
    if (req.method !== 'POST') return send(res, 405, { error: 'Method not allowed.' });
    const body = await readBody(req);
    const action = new URL(req.url, 'https://fable.invalid').searchParams.get('action');
    const email = String(body.email || '').trim().toLowerCase();
    if (!/^[^\s@]+@culkomail\.in$/i.test(email)) return send(res, 400, { error: 'Use your @culkomail.in university email.' });
    if (action === 'request') {
      if (process.env.FABLE_LIVE_ENABLED !== 'true') return send(res, 503, { error: 'Fable sign-in is disabled until its email delivery and privacy contact are configured.' });
      const intent = body.intent === 'signin' ? 'signin' : 'create';
      await supabase('/auth/v1/otp', { method: 'POST', body: { email, create_user: intent === 'create' } });
      return send(res, 200, { ok: true });
    }
    if (action === 'verify') {
      const token = String(body.code || '').replace(/\D/g, '');
      if (!/^\d{6}$/.test(token)) return send(res, 400, { error: 'Enter the six-digit code from your email.' });
      const session = await supabase('/auth/v1/verify', { method: 'POST', body: { email, token, type: 'email' } });
      if (!session?.access_token || !session?.user?.id) return send(res, 401, { error: 'The code is invalid or expired.' });
      return send(res, 200, { access_token: session.access_token, refresh_token: session.refresh_token, expires_at: session.expires_at, user: { id: session.user.id, email: session.user.email } });
    }
    if (action === 'refresh') {
      const refreshToken = String(body.refresh_token || '');
      if (!refreshToken) return send(res, 400, { error: 'Session expired. Sign in again.' });
      const session = await supabase('/auth/v1/token?grant_type=refresh_token', { method: 'POST', body: { refresh_token: refreshToken } });
      return send(res, 200, { access_token: session.access_token, refresh_token: session.refresh_token, expires_at: session.expires_at });
    }
    return send(res, 404, { error: 'Unknown authentication action.' });
  } catch (error) { return send(res, error.status || 500, { error: error.message || 'Authentication failed.' }); }
};

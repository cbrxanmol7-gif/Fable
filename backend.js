/* Browser-side adapter. Authentication tokens live in sessionStorage and only
 * the user's access token is sent to the first-party Vercel API routes. */
(() => {
  const SESSION_KEY = 'fable.auth.session.v1';
  let saving = Promise.resolve();
  let timer;

  function session() {
    try { return JSON.parse(sessionStorage.getItem(SESSION_KEY) || 'null'); }
    catch { return null; }
  }
  function setSession(value) {
    if (value) sessionStorage.setItem(SESSION_KEY, JSON.stringify(value));
    else sessionStorage.removeItem(SESSION_KEY);
  }
  async function send(path, { method = 'GET', body, auth = true } = {}) {
    const headers = { accept: 'application/json' };
    if (body !== undefined) headers['content-type'] = 'application/json';
    let current = session();
    if (auth && current?.access_token) headers.authorization = `Bearer ${current.access_token}`;
    let response = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), credentials: 'same-origin' });
    if (response.status === 401 && auth && current?.refresh_token) {
      const refreshed = await fetch('/api/auth?action=refresh', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ refresh_token: current.refresh_token }) });
      const next = await refreshed.json().catch(() => ({}));
      if (refreshed.ok && next.access_token) {
        current = { ...current, ...next };
        setSession(current);
        headers.authorization = `Bearer ${current.access_token}`;
        response = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), credentials: 'same-origin' });
      } else setSession(null);
    }
    const result = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(result.error || 'Fable could not reach its backend.');
    return result;
  }
  const action = (name, options = {}) => send(`/api/fable?action=${encodeURIComponent(name)}`, options);
  const save = (state) => {
    clearTimeout(timer);
    timer = setTimeout(() => {
      if (!state) return;
      saving = saving.catch(() => {}).then(() => action('state', { method: 'POST', body: { state } })).catch(error => window.fableBackendError?.(error));
    }, 350);
  };

  window.FableBackend = {
    auth: {
      async request(email, intent) {
        return send('/api/auth?action=request', { method: 'POST', auth: false, body: { email, intent } });
      },
      async verify(email, code) {
        const value = await send('/api/auth?action=verify', { method: 'POST', auth: false, body: { email, code } });
        setSession(value);
        return { ok: !!value.access_token, ...value };
      },
      signOut() { setSession(null); }
    },
    async restore() {
      if (!session()?.access_token) return null;
      try { return await action('bootstrap'); }
      catch (error) { if (/sign in|expired|invalid/i.test(error.message)) setSession(null); throw error; }
    },
    async profile(value) { return action('profile', { method: 'POST', body: { profile: value } }); },
    async acceptLegal(termsVersion, privacyVersion) { return action('accept-legal', { method: 'POST', body: { termsVersion, privacyVersion } }); },
    async discover() { return action('discover'); },
    async conversations() { return action('conversations', { method: 'POST', body: {} }); },
    async messages(conversationId) { return action('messages', { method: 'POST', body: { conversationId } }); },
    async sendMessage(conversationId, text, ephemeral) { return action('send-message', { method: 'POST', body: { conversationId, text, ephemeral } }); },
    async createIntro() { return action('intro', { method: 'POST', body: {} }); },
    async respondIntro(introId, accept) { return action('respond-intro', { method: 'POST', body: { introId, accept } }); },
    async endDate(conversationId, continueDate) { return action('end-date', { method: 'POST', body: { conversationId, continue: continueDate } }); },
    async sendInterest(targetId, opener) { return action('interest', { method: 'POST', body: { targetId, opener } }); },
    async interestInbox() { return action('interest-inbox'); },
    async respondInterest(senderId, accept) { return action('respond-interest', { method: 'POST', body: { senderId, accept } }); },
    async report(conversationId, reason, context) { return action('report', { method: 'POST', body: { conversationId, reason, context } }); },
    async moderation() { return action('moderation'); },
    async moderate(reportId, actionName, note) { return action('moderate', { method: 'POST', body: { reportId, action: actionName, note } }); },
    async reviewCorrection(requestId, status) { return action('review-correction', { method: 'POST', body: { requestId, status } }); },
    async block(targetId) { return action('block', { method: 'POST', body: { targetId } }); },
    async correction(note) { return action('correction', { method: 'POST', body: { note } }); },
    async exportData() { return action('export'); },
    async deleteAccount() { return action('account', { method: 'DELETE' }); },
    userId() { return session()?.user?.id || null; },
    async saveProfile(profile) { await saving.catch(() => {}); return action('profile', { method: 'POST', body: { profile } }); },
    save,
    async saveProfile(profile) { await saving.catch(() => {}); return action('profile', { method: 'POST', body: { profile } }); },
    async flush() { clearTimeout(timer); await saving.catch(() => {}); }
  };
})();

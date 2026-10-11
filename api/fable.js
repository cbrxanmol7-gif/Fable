const { send, readBody, supabase, requireUser } = require('./_lib/http');

const rest = (table, query = '') => `/rest/v1/${table}${query}`;
const rpc = (name) => `/rest/v1/rpc/${name}`;
const ownProfile = (id) => `?user_id=eq.${encodeURIComponent(id)}&select=profile_data,created_at,updated_at`;

function storageUrl() {
  const base = process.env.SUPABASE_URL?.replace(/\/$/, '');
  const secret = process.env.SUPABASE_SECRET_KEY;
  if (!base || !secret) throw Object.assign(new Error('Private photo storage is not configured.'), { status: 503 });
  return { base, secret };
}
async function uploadPhoto(userId, dataUrl) {
  const match = /^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/=]+)$/.exec(dataUrl);
  if (!match) throw Object.assign(new Error('Photos must be JPG, PNG, or WebP images.'), { status: 400 });
  const bytes = Buffer.from(match[2], 'base64');
  if (!bytes.length || bytes.length > 1024 * 1024) throw Object.assign(new Error('Each photo must be 1 MB or smaller after resizing.'), { status: 413 });
  const { base, secret } = storageUrl();
  const id = require('node:crypto').randomUUID();
  const ext = match[1] === 'jpeg' ? 'jpg' : match[1];
  const path = `${userId}/${id}.${ext}`;
  const response = await fetch(`${base}/storage/v1/object/fable-profile-photos/${path}`, { method: 'POST', headers: { apikey: secret, authorization: `Bearer ${secret}`, 'content-type': `image/${match[1]}`, 'x-upsert': 'false' }, body: bytes });
  if (!response.ok) throw Object.assign(new Error('Photo upload failed. Try a smaller image.'), { status: 502 });
  return path;
}
async function signPhoto(path, ownerId) {
  if (typeof path !== 'string' || !path.startsWith(`${ownerId}/`)) return null;
  const { base, secret } = storageUrl();
  const response = await fetch(`${base}/storage/v1/object/sign/fable-profile-photos/${path.split('/').map(encodeURIComponent).join('/')}`, { method: 'POST', headers: { apikey: secret, authorization: `Bearer ${secret}`, 'content-type': 'application/json' }, body: JSON.stringify({ expiresIn: 3600 }) });
  if (!response.ok) return null;
  const result = await response.json();
  return result.signedURL?.startsWith('/') ? `${base}/storage/v1${result.signedURL.replace(/^\/storage\/v1/, '')}` : result.signedURL || null;
}
async function displayProfile(profile, ownerId) {
  if (!profile) return null;
  const copy = { ...profile };
  copy.photos = await Promise.all((Array.isArray(copy.photos) ? copy.photos : []).map(path => signPhoto(path, ownerId)));
  return copy;
}
async function removePhotos(userId, paths) {
  const normalized = [...new Set((paths || []).filter(path => typeof path === 'string' && path.startsWith(`${userId}/`)))];
  if (!normalized.length) return;
  const { base, secret } = storageUrl();
  const response = await fetch(`${base}/storage/v1/object/fable-profile-photos`, { method: 'DELETE', headers: { apikey: secret, authorization: `Bearer ${secret}`, 'content-type': 'application/json' }, body: JSON.stringify({ prefixes: normalized }) });
  if (!response.ok) throw Object.assign(new Error('Could not remove private profile photos. Retry account deletion.'), { status: 502 });
}

module.exports = async (req, res) => {
  try {
    const action = new URL(req.url, 'https://fable.invalid').searchParams.get('action');
    const user = await requireUser(req);
    if (req.method === 'GET' && action === 'bootstrap') {
      const [profiles, states, legal] = await Promise.all([
        supabase(rest('fable_profiles', ownProfile(user.id)), { token: user.token }),
        supabase(rest('fable_state', `?user_id=eq.${user.id}&select=state`), { token: user.token }),
        supabase(rest('fable_legal_acceptances', `?user_id=eq.${user.id}&select=terms_version,privacy_version,accepted_at&order=accepted_at.desc&limit=1`), { token: user.token })
      ]);
      return send(res, 200, { profile: await displayProfile(profiles?.[0]?.profile_data, user.id), state: states?.[0]?.state || null, acceptance: legal?.[0] || null, moderator: user.user?.app_metadata?.role === 'moderator', user: { id: user.id, email: user.email } });
    }
    if (req.method === 'GET' && action === 'discover') {
      const rows = await supabase(rpc('fable_discover_profiles'), { method: 'POST', token: user.token, body: {} });
      return send(res, 200, { profiles: rows || [] });
    }
    if (req.method === 'GET' && action === 'interest-inbox') {
      const rows = await supabase(rpc('fable_interest_inbox'), { method: 'POST', token: user.token, body: {} });
      return send(res, 200, { requests: rows || [] });
    }
    if (req.method === 'GET' && action === 'moderation') {
      const [reports, corrections] = await Promise.all([
        supabase(rpc('fable_moderation_queue'), { method: 'POST', token: user.token, body: {} }),
        supabase(rpc('fable_correction_queue'), { method: 'POST', token: user.token, body: {} })
      ]);
      return send(res, 200, { reports: reports || [], corrections: corrections || [] });
    }
    if (req.method === 'POST') {
      const body = await readBody(req);
      if (action === 'profile') {
        if (!body.profile || typeof body.profile !== 'object') return send(res, 400, { error: 'Profile data is required.' });
        const profile = { ...body.profile };
        delete profile.email; delete profile.correctionRequests;
        if (Number(profile.age) < 18 || Number(profile.age) > 99) return send(res, 400, { error: 'Fable is for adults aged 18 and over.' });
        profile.photos = await Promise.all((Array.isArray(profile.photos) ? profile.photos : []).slice(0, 3).map(async photo => {
          if (!photo) return null;
          if (typeof photo === 'string' && photo.startsWith('data:image/')) return uploadPhoto(user.id, photo);
          if (typeof photo === 'string' && photo.startsWith(`${user.id}/`)) return photo;
          if (typeof photo === 'string' && photo.includes('/storage/v1/object/sign/fable-profile-photos/')) {
            const path = decodeURIComponent(photo.split('/storage/v1/object/sign/fable-profile-photos/')[1].split('?')[0]);
            return path.startsWith(`${user.id}/`) ? path : null;
          }
          return null;
        }));
        if (JSON.stringify(profile).length > 18000) return send(res, 413, { error: 'Profile is too large.' });
        const before = await supabase(rest('fable_profiles', ownProfile(user.id)), { token: user.token });
        const saved = await supabase(rest('fable_profiles'), { method: 'POST', token: user.token, body: { user_id: user.id, profile_data: profile }, prefer: 'resolution=merge-duplicates,return=representation' });
        const keep = new Set(profile.photos.filter(Boolean));
        await removePhotos(user.id, (before?.[0]?.profile_data?.photos || []).filter(path => !keep.has(path)));
        return send(res, 200, { profile: await displayProfile(saved?.[0]?.profile_data || profile, user.id) });
      }
      if (action === 'state') {
        if (!body.state || typeof body.state !== 'object') return send(res, 400, { error: 'Account state is required.' });
        const safe = { ...body.state };
        delete safe.email; delete safe.profile;
        delete safe.th; delete safe.chat; delete safe.bd;
        if (JSON.stringify(safe).length > 18000) return send(res, 413, { error: 'Account settings are too large.' });
        await supabase(rest('fable_state'), { method: 'POST', token: user.token, body: { user_id: user.id, state: safe }, prefer: 'resolution=merge-duplicates,return=minimal' });
        return send(res, 200, { ok: true });
      }
      if (action === 'intro') {
        const rows = await supabase(rpc('fable_request_blind_intro'), { method: 'POST', token: user.token, body: {} });
        return send(res, 200, { intro: rows?.[0] || null });
      }
      if (action === 'respond-intro') {
        const rows = await supabase(rpc('fable_respond_blind_intro'), { method: 'POST', token: user.token, body: { p_intro_id: body.introId, p_accept: body.accept === true } });
        return send(res, 200, { result: rows?.[0] || null });
      }
      if (action === 'interest') {
        const rows = await supabase(rpc('fable_send_interest'), { method: 'POST', token: user.token, body: { p_target_id: body.targetId, p_opener: String(body.opener || '').slice(0, 300) } });
        return send(res, 200, { result: rows?.[0] || null });
      }
      if (action === 'respond-interest') {
        const rows = await supabase(rpc('fable_respond_interest'), { method: 'POST', token: user.token, body: { p_sender_id: body.senderId, p_accept: body.accept === true } });
        return send(res, 200, { result: rows?.[0] || null });
      }
      if (action === 'conversations') {
        const rows = await supabase(rpc('fable_list_conversations'), { method: 'POST', token: user.token, body: {} });
        const conversations = await Promise.all((rows || []).map(async row => {
          if (row.profile?.photos) row.profile = await displayProfile(row.profile, row.member_id);
          return row;
        }));
        return send(res, 200, { conversations });
      }
      if (action === 'messages') {
        const rows = await supabase(rpc('fable_list_messages'), { method: 'POST', token: user.token, body: { p_conversation_id: body.conversationId } });
        return send(res, 200, { messages: rows || [] });
      }
      if (action === 'send-message') {
        const rows = await supabase(rpc('fable_send_message'), { method: 'POST', token: user.token, body: { p_conversation_id: body.conversationId, p_text: String(body.text || '').trim().slice(0, 2000), p_ephemeral: body.ephemeral === true } });
        return send(res, 201, { message: rows?.[0] || null });
      }
      if (action === 'report') {
        const rows = await supabase(rpc('fable_submit_report'), { method: 'POST', token: user.token, body: { p_conversation_id: body.conversationId || null, p_reason: String(body.reason || '').slice(0, 80), p_context: Array.isArray(body.context) ? body.context.slice(-4) : [] } });
        return send(res, 201, { report: rows?.[0] || null });
      }
      if (action === 'block') {
        await supabase(rpc('fable_block_user'), { method: 'POST', token: user.token, body: { p_target_id: body.targetId } });
        return send(res, 200, { ok: true });
      }
      if (action === 'correction') {
        const rows = await supabase(rpc('fable_request_correction'), { method: 'POST', token: user.token, body: { p_note: String(body.note || '').trim().slice(0, 300) } });
        return send(res, 201, { request: rows?.[0] || null });
      }
      if (action === 'accept-legal') {
        await supabase(rpc('fable_accept_legal'), { method: 'POST', token: user.token, body: { p_terms_version: String(body.termsVersion || ''), p_privacy_version: String(body.privacyVersion || '') } });
        return send(res, 200, { ok: true });
      }
      if (action === 'end-date') {
        const rows = await supabase(rpc('fable_end_date'), { method: 'POST', token: user.token, body: { p_conversation_id: body.conversationId, p_continue: body.continue === true } });
        return send(res, 200, { result: rows?.[0] || null });
      }
      if (action === 'moderate') {
        await supabase(rpc('fable_moderate_report'), { method: 'POST', token: user.token, body: { p_report_id: body.reportId, p_action: body.action, p_note: String(body.note || '').slice(0, 500) } });
        return send(res, 200, { ok: true });
      }
      if (action === 'review-correction') {
        await supabase(rpc('fable_review_correction'), { method: 'POST', token: user.token, body: { p_request_id: body.requestId, p_status: body.status } });
        return send(res, 200, { ok: true });
      }
    }
    if (req.method === 'GET' && action === 'export') {
      const result = await supabase(rpc('fable_export_data'), { method: 'POST', token: user.token, body: {} });
      result.email = user.email;
      result.profile = await displayProfile(result.profile, user.id);
      return send(res, 200, result);
    }
    if (req.method === 'DELETE' && action === 'account') {
      const key = process.env.SUPABASE_SECRET_KEY;
      if (!key) return send(res, 503, { error: 'Account deletion is not configured yet.' });
      const profile = await supabase(rest('fable_profiles', ownProfile(user.id)), { token: user.token });
      await removePhotos(user.id, profile?.[0]?.profile_data?.photos || []);
      await supabase(`/auth/v1/admin/users/${user.id}`, { method: 'DELETE', token: key, admin: true });
      return send(res, 200, { ok: true });
    }
    return send(res, 404, { error: 'Unknown backend action.' });
  } catch (error) { return send(res, error.status || 500, { error: error.message || 'Backend request failed.' }); }
};

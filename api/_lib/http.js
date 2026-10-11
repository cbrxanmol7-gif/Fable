const MAX_BODY = 3 * 1024 * 1024;

function send(res, status, payload) {
  res.status(status).setHeader('content-type', 'application/json; charset=utf-8');
  res.setHeader('cache-control', 'no-store');
  res.end(JSON.stringify(payload));
}

async function readBody(req) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY) throw Object.assign(new Error('Request is too large.'), { status: 413 });
    chunks.push(chunk);
  }
  if (!size) return {};
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw Object.assign(new Error('Invalid JSON body.'), { status: 400 }); }
}

function config() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY;
  if (!url || !key) throw Object.assign(new Error('Backend is not configured. Add SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in Vercel.'), { status: 503 });
  return { url: url.replace(/\/$/, ''), key };
}

async function supabase(path, { method = 'GET', token, body, prefer, admin = false } = {}) {
  const { url, key } = config();
  const apiKey = admin ? process.env.SUPABASE_SECRET_KEY : key;
  if (!apiKey) throw Object.assign(new Error('Admin backend key is not configured.'), { status: 503 });
  const headers = { apikey: apiKey, authorization: `Bearer ${token || apiKey}` };
  if (body !== undefined) headers['content-type'] = 'application/json';
  if (prefer) headers.prefer = prefer;
  const response = await fetch(`${url}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await response.text();
  let result;
  try { result = text ? JSON.parse(text) : null; } catch { result = { message: text.slice(0, 500) }; }
  if (!response.ok) {
    const message = result?.msg || result?.message || result?.error_description || 'Backend request failed.';
    throw Object.assign(new Error(message), { status: response.status >= 500 ? 502 : response.status });
  }
  return result;
}

async function requireUser(req) {
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
  if (!token) throw Object.assign(new Error('Sign in to continue.'), { status: 401 });
  const user = await supabase('/auth/v1/user', { token });
  if (!user?.id || !/^[^\s@]+@culkomail\.in$/i.test(user.email || '')) {
    throw Object.assign(new Error('Use a verified CU UP email address.'), { status: 403 });
  }
  return { id: user.id, email: user.email.toLowerCase(), token, user };
}

module.exports = { send, readBody, supabase, requireUser };

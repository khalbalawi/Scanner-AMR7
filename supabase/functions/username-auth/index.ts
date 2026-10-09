import { createClient } from 'npm:@supabase/supabase-js@2'

const allowedOrigins = new Set([
  'https://scanner9.work',
  'http://localhost:4173',
  'http://127.0.0.1:4173',
])

function corsHeaders(req: Request) {
  const origin = req.headers.get('origin') || ''
  return {
    'Access-Control-Allow-Origin': allowedOrigins.has(origin) ? origin : 'https://scanner9.work',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Content-Type': 'application/json; charset=utf-8',
    'Vary': 'Origin',
  }
}

function reply(req: Request, body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders(req) })
}

function normalizeUsername(value: unknown) {
  return String(value || '').normalize('NFKC').trim().toLowerCase()
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) })
  if (req.method !== 'POST') return reply(req, { error: 'Method not allowed' }, 405)

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const publicKey = Deno.env.get('SUPABASE_ANON_KEY') || Deno.env.get('SUPABASE_PUBLISHABLE_KEY')
  const secretKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SECRET_KEY')
  if (!supabaseUrl || !publicKey || !secretKey) return reply(req, { error: 'Authentication is unavailable' }, 503)

  let body: { username?: string; password?: string }
  try {
    body = await req.json()
  } catch {
    return reply(req, { error: 'Invalid request body' }, 400)
  }

  const usernameKey = normalizeUsername(body.username)
  const password = String(body.password || '')
  if (usernameKey.length < 3 || password.length < 8) {
    return reply(req, { error: 'Invalid username or password' }, 400)
  }

  const adminClient = createClient(supabaseUrl, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: profile, error: profileError } = await adminClient
    .from('user_profiles')
    .select('email')
    .eq('username_key', usernameKey)
    .maybeSingle()

  if (profileError || !profile?.email) return reply(req, { error: 'Invalid username or password' }, 401)

  const authClient = createClient(supabaseUrl, publicKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data, error } = await authClient.auth.signInWithPassword({
    email: profile.email,
    password,
  })

  if (error || !data.session) return reply(req, { error: 'Invalid username or password' }, 401)

  return reply(req, {
    session: {
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
    },
  })
})

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

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) })
  if (req.method !== 'POST') return reply(req, { error: 'Method not allowed' }, 405)

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const publicKey = Deno.env.get('SUPABASE_ANON_KEY') || Deno.env.get('SUPABASE_PUBLISHABLE_KEY')
  const secretKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SECRET_KEY')
  const authorization = req.headers.get('Authorization')

  if (!supabaseUrl || !publicKey || !secretKey || !authorization) {
    return reply(req, { error: 'Unauthorized' }, 401)
  }

  const userClient = createClient(supabaseUrl, publicKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  })
  const adminClient = createClient(supabaseUrl, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const token = authorization.replace(/^Bearer\s+/i, '')
  const { data: authData, error: authError } = await userClient.auth.getUser(token)
  if (authError || !authData.user) return reply(req, { error: 'Unauthorized' }, 401)

  const { data: callerProfile } = await adminClient
    .from('user_profiles')
    .select('role')
    .eq('user_id', authData.user.id)
    .maybeSingle()
  if (callerProfile?.role !== 'admin') return reply(req, { error: 'Admin access required' }, 403)

  let body: { email?: string; password?: string; displayName?: string; siteId?: number }
  try {
    body = await req.json()
  } catch {
    return reply(req, { error: 'Invalid request body' }, 400)
  }

  const email = String(body.email || '').trim().toLowerCase()
  const password = String(body.password || '')
  const displayName = String(body.displayName || '').trim()
  const siteId = Number(body.siteId)

  if (!/^\S+@\S+\.\S+$/.test(email)) return reply(req, { error: 'Valid email is required' }, 400)
  if (password.length < 8) return reply(req, { error: 'Password must be at least 8 characters' }, 400)
  if (!displayName) return reply(req, { error: 'Display name is required' }, 400)
  if (!Number.isSafeInteger(siteId) || siteId <= 0) return reply(req, { error: 'Site is required' }, 400)

  const { data: site, error: siteError } = await adminClient
    .from('inventory_sites')
    .select('id,site_type,name_ar,name_en')
    .eq('id', siteId)
    .eq('is_active', true)
    .single()
  if (siteError || !site) return reply(req, { error: 'Selected site is unavailable' }, 400)

  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { display_name: displayName },
  })
  if (createError || !created.user) {
    return reply(req, { error: createError?.message || 'Could not create user' }, 400)
  }

  const { error: profileError } = await adminClient.from('user_profiles').upsert({
    user_id: created.user.id,
    email,
    display_name: displayName,
    role: 'user',
    site_type: site.site_type,
    site_name: site.name_ar,
    updated_at: new Date().toISOString(),
  }, { onConflict: 'user_id' })

  if (profileError) {
    await adminClient.auth.admin.deleteUser(created.user.id)
    return reply(req, { error: 'Could not assign the site to the new user' }, 500)
  }

  return reply(req, {
    user: {
      id: created.user.id,
      email,
      display_name: displayName,
      role: 'user',
      site_type: site.site_type,
      site_name: site.name_ar,
    },
  }, 201)
})

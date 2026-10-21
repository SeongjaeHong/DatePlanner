import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'METHOD_NOT_ALLOWED' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authorization = request.headers.get('Authorization');
  if (!url || !anonKey || !serviceKey || !authorization?.startsWith('Bearer ')) {
    return json({ error: 'NOT_CONFIGURED' }, 503);
  }

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser(authorization.slice(7));
  if (authError || !user) return json({ error: 'NOT_AUTHENTICATED' }, 401);

  let body: { operation_id?: string; expected_member_count?: number; confirmation_word?: string };
  try {
    body = await request.json();
  } catch {
    return json({ error: 'INVALID_REQUEST' }, 400);
  }
  if (!body.operation_id || ![1, 2].includes(body.expected_member_count ?? 0) ||
      body.confirmation_word?.trim().toUpperCase() !== 'DELETE') {
    return json({ error: 'CONFIRMATION_REQUIRED' }, 400);
  }

  const { data: leave, error: leaveError } = await userClient.rpc('leave_space', {
    p_operation_id: body.operation_id,
    p_expected_member_count: body.expected_member_count,
    p_confirmation_word: body.confirmation_word,
  });
  if (leaveError || leave?.error_code || leave?.result === 'reconfirm_required') {
    return json({ error: leave?.error_code ?? leave?.result ?? 'LEAVE_FAILED' }, 409);
  }

  // Attempt queued object removal before Auth deletion. A failed object removal
  // remains durable in the queue and can be retried by a later worker run.
  try {
    await fetch(`${url}/functions/v1/drain-file-deletion-queue`, {
      method: 'POST',
      headers: { Authorization: authorization, apikey: anonKey, 'Content-Type': 'application/json' },
      body: '{}',
    });
  } catch { /* queue remains available for a retry */ }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) return json({ error: 'AUTH_DELETE_FAILED' }, 502);
  return json({ deleted: true }, 200);
});

function json(value: unknown, status: number) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

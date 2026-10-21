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
  const authClient = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: { user }, error: authError } = await authClient.auth.getUser(authorization.slice(7));
  if (authError || !user) return json({ error: 'NOT_AUTHENTICATED' }, 401);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: rows, error: queueError } = await admin.from('file_deletion_queue')
    .select('id,bucket_id,object_path,attempts').order('queued_at').limit(100);
  if (queueError) return json({ error: 'QUEUE_READ_FAILED' }, 500);

  let removed = 0;
  let failed = 0;
  for (const row of rows ?? []) {
    const { error } = await admin.storage.from(row.bucket_id).remove([row.object_path]);
    if (error) {
      failed++;
      await admin.from('file_deletion_queue').update({
        attempts: row.attempts + 1,
        last_error: error.message.slice(0, 500),
      }).eq('id', row.id);
    } else {
      const { error: deleteRowError } = await admin.from('file_deletion_queue').delete().eq('id', row.id);
      if (deleteRowError) failed++;
      else removed++;
    }
  }
  return json({ removed, failed }, 200);
});

function json(value: unknown, status: number) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

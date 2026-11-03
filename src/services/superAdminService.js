import { supabase } from '@/lib/supabase'

function unwrap({ data, error }) {
  if (error) throw new Error(error.message)
  return data
}

export async function listAuditLogs({ action = '', entityType = '', from = '', to = '' } = {}) {
  let query = supabase
    .from('audit_logs')
    .select('id, actor_id, actor_role, action, entity_type, entity_id, before, after, created_at')
    .order('created_at', { ascending: false })
    .limit(500)
  if (action.trim()) query = query.ilike('action', `%${action.trim()}%`)
  if (entityType) query = query.eq('entity_type', entityType)
  if (from) query = query.gte('created_at', from)
  if (to) query = query.lte('created_at', to)
  return unwrap(await query)
}

export async function getSikpMapping() {
  return unwrap(await supabase.from('sikp_export_mapping').select('columns, updated_at').eq('id', true).single())
}

export async function saveSikpMapping(columns) {
  return unwrap(await supabase.rpc('super_admin_update_sikp_mapping', { p_columns: columns }))
}

export async function exportSikp(from, to) {
  return unwrap(await supabase.rpc('super_admin_export_sikp', { p_from: from, p_to: to }))
}

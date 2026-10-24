import { supabase } from '@/lib/supabase'

export async function listUsers({ q = '', role = '', page = 1, pageSize = 15 } = {}) {
  let query = supabase
    .from('profiles')
    .select('id, full_name, phone, role, created_at', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range((page - 1) * pageSize, page * pageSize - 1)
  if (role) query = query.eq('role', role)
  const term = q.trim().replace(/[%,()]/g, ' ')
  if (term) query = query.ilike('full_name', `%${term}%`)
  const { data, error, count } = await query
  if (error) throw new Error(error.message)
  return { items: data, total: count ?? 0 }
}

export async function setUserRole(id, role) {
  const { error } = await supabase.rpc('admin_set_user_role', { p_user_id: id, p_role: role })
  if (error) throw new Error(error.message)
}

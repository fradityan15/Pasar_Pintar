import { supabase } from '@/lib/supabase'

export async function listAddresses() {
  const { data, error } = await supabase
    .from('addresses')
    .select('id, label, recipient_name, phone, province, city, street, postal_code, is_default')
    .order('is_default', { ascending: false })
    .order('created_at', { ascending: false })
  if (error) throw new Error(error.message)
  return data
}

export async function createAddress(userId, form, isDefault) {
  const { data, error } = await supabase
    .from('addresses')
    .insert({ ...form, user_id: userId, is_default: isDefault })
    .select('id')
    .single()
  if (error) throw new Error(error.message)
  return data
}

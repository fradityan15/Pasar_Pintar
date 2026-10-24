import { supabase } from '@/lib/supabase'

const take = ({ data, error }) => {
  if (error) throw new Error(error.message)
  return data
}

export async function updateProfile(userId, { full_name, phone }) {
  take(await supabase.from('profiles').update({ full_name, phone: phone || null }).eq('id', userId))
}

export async function updatePassword(password) {
  const { error } = await supabase.auth.updateUser({ password })
  if (error) throw new Error(error.message)
}

export async function updateAddress(id, fields) {
  take(await supabase.from('addresses').update(fields).eq('id', id))
}

export async function deleteAddress(id) {
  take(await supabase.from('addresses').delete().eq('id', id))
}

// Hanya satu alamat utama per pengguna (indeks unik): lepas yang lama dulu, lalu set yang baru.
export async function setDefaultAddress(userId, id) {
  take(await supabase.from('addresses').update({ is_default: false }).eq('user_id', userId).eq('is_default', true))
  take(await supabase.from('addresses').update({ is_default: true }).eq('id', id))
}

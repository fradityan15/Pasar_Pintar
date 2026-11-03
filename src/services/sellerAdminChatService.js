import { supabase } from '@/lib/supabase'

function unwrap({ data, error }) {
  if (error) throw new Error(error.message)
  return data
}

export async function listSellerAdminMessages(umkmId) {
  return unwrap(await supabase.rpc('seller_list_admin_messages', { p_umkm_id: umkmId }))
}

export async function sendSellerAdminMessage(umkmId, body) {
  return unwrap(await supabase.rpc('seller_send_admin_message', {
    p_umkm_id: umkmId,
    p_body: body,
  }))
}

export async function listAdminSellerMessageThreads() {
  return unwrap(await supabase.rpc('admin_list_seller_message_threads'))
}

export async function listAdminSellerMessages(umkmId) {
  return unwrap(await supabase.rpc('admin_list_seller_messages', { p_umkm_id: umkmId }))
}

export async function sendAdminSellerMessage(umkmId, body) {
  return unwrap(await supabase.rpc('admin_send_seller_message', {
    p_umkm_id: umkmId,
    p_body: body,
  }))
}

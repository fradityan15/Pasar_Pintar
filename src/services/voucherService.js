import { supabase } from '@/lib/supabase'

function unwrap({ data, error }) {
  if (error) throw new Error(error.message)
  return data
}

const VOUCHER_FIELDS = [
  'id', 'code', 'discount_type', 'discount_value', 'maximum_discount',
  'minimum_purchase', 'quota_total', 'quota_used', 'berlaku_dari',
  'berlaku_sampai', 'is_active', 'scope_type', 'umkm_ids', 'category_ids',
].join(', ')

export async function listActiveVouchers() {
  return unwrap(await supabase.from('vouchers')
    .select(VOUCHER_FIELDS)
    .eq('is_active', true)
    .order('berlaku_sampai'))
}

export async function listMyVoucherClaims() {
  return unwrap(await supabase.rpc('my_voucher_claims'))
}

export async function claimVoucher(code) {
  return unwrap(await supabase.rpc('claim_voucher', { p_code: code }))
}

export async function listVouchersAdmin() {
  return unwrap(await supabase.from('vouchers')
    .select(VOUCHER_FIELDS)
    .order('created_at', { ascending: false }))
}

export async function listVoucherClaimReport() {
  return unwrap(await supabase.from('voucher_claims')
    .select('id, voucher_id, user_id, order_id, status, claimed_at, used_at, vouchers!inner(code), profiles(full_name)')
    .order('claimed_at', { ascending: false })
    .limit(500))
}

export async function listVoucherScopeOptions() {
  const [stores, categories] = await Promise.all([
    supabase.from('umkm').select('id, name').order('name'),
    supabase.from('categories').select('id, name').order('name'),
  ])
  if (stores.error) throw new Error(stores.error.message)
  if (categories.error) throw new Error(categories.error.message)
  return { stores: stores.data ?? [], categories: categories.data ?? [] }
}

export async function saveVoucher(id, fields) {
  const query = id
    ? supabase.from('vouchers').update(fields).eq('id', id)
    : supabase.from('vouchers').insert(fields)
  unwrap(await query)
}

export async function deleteVoucher(id) {
  unwrap(await supabase.from('vouchers').delete().eq('id', id))
}

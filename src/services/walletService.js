import { supabase } from '@/lib/supabase'

function unwrap({ data, error }) {
  if (error) throw new Error(error.message)
  return data
}

export async function getSellerWalletSummary(umkmId) {
  return unwrap(await supabase.rpc('seller_wallet_summary', { p_umkm_id: umkmId }))
}

export async function getSellerPaidPayoutSummary(umkmId) {
  return unwrap(await supabase.rpc('seller_paid_payout_summary', { p_umkm_id: umkmId }))
}

export async function listSellerLedger(umkmId) {
  return unwrap(
    await supabase
      .from('wallet_ledger')
      .select('id, entry_type, amount, order_id, withdrawal_id, created_at')
      .eq('umkm_id', umkmId)
      .order('created_at', { ascending: false })
      .limit(100),
  )
}

export async function listSellerWithdrawals(umkmId) {
  return unwrap(
    await supabase
      .from('withdrawal_requests')
      .select('id, amount, status, bank_snapshot, admin_note, requested_at, reviewed_at, paid_at')
      .eq('umkm_id', umkmId)
      .order('requested_at', { ascending: false })
      .limit(50),
  )
}

export async function requestSellerWithdrawal(amount, idempotencyKey = crypto.randomUUID()) {
  return unwrap(await supabase.rpc('request_withdrawal', {
    p_amount: amount,
    p_idempotency_key: idempotencyKey,
  }))
}

export async function listAdminWithdrawals() {
  return unwrap(await supabase.rpc('admin_list_withdrawals'))
}

export async function processAdminWithdrawal(withdrawalId, decision, note = '') {
  return unwrap(await supabase.rpc('admin_process_withdrawal', {
    p_withdrawal_id: withdrawalId,
    p_decision: decision,
    p_note: note || null,
  }))
}

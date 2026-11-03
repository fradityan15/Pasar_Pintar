import { supabase } from '@/lib/supabase'

function unwrap({ data, error }) {
  if (error) throw new Error(error.message)
  return data
}

export async function loadMyLoyaltyWallet() {
  const [ledger, settings] = await Promise.all([
    supabase.from('loyalty_ledger')
      .select('id, entry_type, points, order_id, created_at, expires_at')
      .order('created_at', { ascending: false }),
    supabase.from('loyalty_settings')
      .select('earn_points_per_step, earn_amount_step, redemption_value, max_redeem_points_per_order')
      .eq('id', true)
      .single(),
  ])
  const entries = unwrap(ledger) ?? []
  return {
    entries,
    balance: entries.reduce((sum, entry) => sum + entry.points, 0),
    settings: unwrap(settings),
  }
}

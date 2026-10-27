import { supabase } from '@/lib/supabase'

export async function salesReport(from, to) {
  const { data, error } = await supabase.rpc('sales_report', { p_from: from, p_to: to })
  if (error) throw new Error(error.message)
  return data
}

// Agregasi dilakukan di database agar laporan tidak terpotong oleh batas baris API.
export async function topProducts(from, to, limit = 5) {
  const { data, error } = await supabase.rpc('top_products_report', {
    p_from: from,
    p_to: to,
    p_limit: limit,
  })
  if (error) throw new Error(error.message)

  return (data ?? []).map((row) => ({
    name: row.product_name,
    qty: Number(row.quantity),
    revenue: Number(row.revenue),
  }))
}

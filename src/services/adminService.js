import { supabase } from '@/lib/supabase'

export async function getDashboardStats() {
  const { data, error } = await supabase.rpc('dashboard_stats')
  if (error) throw new Error(error.message)
  return data
}

export async function getAdminDashboardCharts() {
  const { data, error } = await supabase.rpc('admin_dashboard_charts')
  if (error) throw new Error(error.message)
  return data
}

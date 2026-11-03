import { supabase } from '@/lib/supabase'

export async function searchRajaOngkirAreas(query) {
  const normalizedQuery = query.trim()
  if (normalizedQuery.length < 2 || normalizedQuery.length > 80) {
    throw new Error('Masukkan minimal 2 karakter untuk mencari wilayah.')
  }

  const { data, error } = await supabase.functions.invoke('search-rajaongkir-areas', {
    body: { query: normalizedQuery },
  })

  if (error) {
    const response = error.context
    if (response instanceof Response) {
      console.error('Pencarian wilayah RajaOngkir gagal:', {
        status: response.status,
        body: await response.clone().text(),
      })
    } else {
      console.error('Gagal memanggil fungsi pencarian wilayah RajaOngkir:', error)
    }
    throw new Error(data?.error || 'Wilayah tidak dapat dicari. Coba lagi.')
  }
  if (!data || !Array.isArray(data.areas)) {
    throw new Error('Respons pencarian wilayah tidak valid.')
  }
  return data.areas
}

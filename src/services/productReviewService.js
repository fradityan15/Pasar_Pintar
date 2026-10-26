import { supabase } from '@/lib/supabase'

function unwrap({ data, error }) {
  if (error) throw new Error(error.message)
  return data
}

export async function listProductReviews(productId) {
  return unwrap(
    await supabase
      .from('product_reviews')
      .select('id, rating, comment, created_at')
      .eq('product_id', productId)
      .order('created_at', { ascending: false }),
  )
}

export async function listMyReviewedProductIds() {
  return unwrap(await supabase.rpc('get_my_reviewed_product_ids'))
}

export async function createProductReview({ productId, userId, rating, comment }) {
  unwrap(
    await supabase.from('product_reviews').insert({
      product_id: productId,
      user_id: userId,
      rating,
      comment: comment.trim() || null,
    }),
  )
}

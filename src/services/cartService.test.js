import { beforeEach, describe, expect, it, vi } from 'vitest'

const { supabaseMock, queryMock } = vi.hoisted(() => ({
  supabaseMock: { from: vi.fn() },
  queryMock: {
    select: vi.fn(),
    order: vi.fn(),
    upsert: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    eq: vi.fn(),
  },
}))

vi.mock('@/lib/supabase', () => ({ supabase: supabaseMock }))

import {
  deleteCartItem,
  fetchCart,
  updateCartQuantity,
  upsertCartItem,
} from './cartService.js'

describe('cart service', () => {
  beforeEach(() => {
    supabaseMock.from.mockReturnValue(queryMock)
    queryMock.select.mockReturnValue(queryMock)
    queryMock.order.mockResolvedValue({ data: [{ id: 'item-1' }], error: null })
    queryMock.upsert.mockResolvedValue({ error: null })
    queryMock.update.mockReturnValue(queryMock)
    queryMock.delete.mockReturnValue(queryMock)
    queryMock.eq.mockResolvedValue({ error: null })
  })

  it('fetches cart items', async () => {
    await expect(fetchCart()).resolves.toEqual([{ id: 'item-1' }])
    expect(supabaseMock.from).toHaveBeenCalledWith('cart_items')
    expect(queryMock.order).toHaveBeenCalledWith('id')
  })

  it('adds or merges a cart item by user and product', async () => {
    await upsertCartItem('user-1', 'product-1', 2)

    expect(queryMock.upsert).toHaveBeenCalledWith(
      { user_id: 'user-1', product_id: 'product-1', quantity: 2 },
      { onConflict: 'user_id,product_id' },
    )
  })

  it('updates an item quantity', async () => {
    await updateCartQuantity('item-1', 4)

    expect(queryMock.update).toHaveBeenCalledWith({ quantity: 4 })
    expect(queryMock.eq).toHaveBeenCalledWith('id', 'item-1')
  })

  it('deletes an item', async () => {
    await deleteCartItem('item-1')

    expect(queryMock.delete).toHaveBeenCalled()
    expect(queryMock.eq).toHaveBeenCalledWith('id', 'item-1')
  })
})

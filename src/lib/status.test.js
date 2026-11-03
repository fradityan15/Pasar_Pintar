import { describe, expect, it } from 'vitest'
import { ORDER_STATUS, PAYMENT_METHOD } from './status.js'

describe('order and payment status helpers', () => {
  it('exposes labels and styles for each supported order state', () => {
    expect(Object.keys(ORDER_STATUS)).toEqual([
      'menunggu_pembayaran',
      'menunggu_diproses',
      'diproses',
      'dikirim',
      'selesai',
      'dibatalkan',
    ])
    expect(ORDER_STATUS.menunggu_pembayaran.label).toBe('Menunggu pembayaran')
    expect(ORDER_STATUS.selesai.cls).toContain('text-ok-fg')
  })

  it('exposes supported payment labels', () => {
    expect(PAYMENT_METHOD.qris).toBe('QRIS')
    expect(PAYMENT_METHOD.virtual_account).toBe('Virtual Account')
  })
})

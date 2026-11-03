import { beforeEach, describe, expect, it, vi } from 'vitest'

const { mocks } = vi.hoisted(() => ({
  mocks: { auth: null, getMyUmkm: vi.fn() },
}))

vi.mock('@/stores/auth', () => ({ useAuthStore: () => mocks.auth }))
vi.mock('@/services/umkmPartnerService', () => ({ getMyUmkm: mocks.getMyUmkm }))

import router from './index.js'

function setAuth({ loggedIn = false, admin = false, superAdmin = false, profileError = '' } = {}) {
  mocks.auth = {
    init: vi.fn().mockResolvedValue(),
    isLoggedIn: loggedIn,
    isAdmin: admin,
    isSuperAdmin: superAdmin,
    profileError,
  }
}

describe('router access guards', () => {
  beforeEach(async () => {
    setAuth()
    mocks.getMyUmkm.mockResolvedValue(null)
    await router.push('/')
  })

  it('allows a guest to open the login page', async () => {
    await router.push('/masuk')

    expect(router.currentRoute.value.name).toBe('login')
  })

  it('redirects an unauthenticated user from a protected page to login', async () => {
    await router.push('/akun')

    expect(router.currentRoute.value.name).toBe('login')
    expect(router.currentRoute.value.query.redirect).toBe('/akun')
  })

  it('allows an authenticated UMKM owner to open admin chat', async () => {
    setAuth({ loggedIn: true })
    mocks.getMyUmkm.mockResolvedValue({ id: 'umkm-1', status: 'active' })

    await router.push('/mitra/chat-admin')

    expect(router.currentRoute.value.name).toBe('umkm-admin-chat')
    expect(mocks.getMyUmkm).toHaveBeenCalled()
  })

  it('blocks an authenticated user without an UMKM application', async () => {
    setAuth({ loggedIn: true })

    await router.push('/mitra/pesanan')

    expect(router.currentRoute.value.name).toBe('home')
    expect(router.currentRoute.value.query.accessDenied).toBe('1')
  })

  it('allows an admin to open seller messages', async () => {
    setAuth({ loggedIn: true, admin: true })

    await router.push('/admin/pesan-penjual')

    expect(router.currentRoute.value.name).toBe('admin-pesan-penjual')
  })

  it('blocks a non-admin from admin pages', async () => {
    setAuth({ loggedIn: true })

    await router.push('/admin/ringkasan')

    expect(router.currentRoute.value.name).toBe('home')
    expect(router.currentRoute.value.query.accessDenied).toBe('1')
  })

  it('blocks an admin from Super Admin pages', async () => {
    setAuth({ loggedIn: true, admin: true })

    await router.push('/admin/audit-log')

    expect(router.currentRoute.value.name).toBe('home')
    expect(router.currentRoute.value.query.accessDenied).toBe('1')
  })

  it('allows a Super Admin to open SIKP export', async () => {
    setAuth({ loggedIn: true, admin: true, superAdmin: true })

    await router.push('/admin/sikp')

    expect(router.currentRoute.value.name).toBe('admin-sikp')
  })
})

import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

const { supabaseMock } = vi.hoisted(() => ({
  supabaseMock: {
    auth: {
      signInWithPassword: vi.fn(),
      getSession: vi.fn(),
      signOut: vi.fn(),
    },
    from: vi.fn(),
  },
}))

vi.mock('@/lib/supabase', () => ({ supabase: supabaseMock }))

import { useAuthStore } from './auth.js'

function mockProfileQuery(result) {
  const query = {
    select: vi.fn(),
    eq: vi.fn(),
    maybeSingle: vi.fn().mockResolvedValue(result),
  }
  query.select.mockReturnValue(query)
  query.eq.mockReturnValue(query)
  supabaseMock.from.mockReturnValue(query)
}

describe('auth store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    supabaseMock.auth.signInWithPassword.mockResolvedValue({ error: null })
    supabaseMock.auth.getSession.mockResolvedValue({
      data: { session: { user: { id: 'user-1', email: 'user@example.test' } } },
    })
    supabaseMock.auth.signOut.mockResolvedValue({ error: null })
    mockProfileQuery({
      data: { id: 'user-1', full_name: 'User Test', role: 'admin' },
      error: null,
    })
  })

  it('signs in and loads the profile', async () => {
    const auth = useAuthStore()

    await auth.signIn('user@example.test', 'secret')

    expect(supabaseMock.auth.signInWithPassword).toHaveBeenCalledWith({
      email: 'user@example.test',
      password: 'secret',
    })
    expect(auth.user.id).toBe('user-1')
    expect(auth.profile.role).toBe('admin')
    expect(auth.isAdmin).toBe(true)
  })

  it('signs out and clears user profile state', async () => {
    const auth = useAuthStore()
    auth.user = { id: 'user-1' }
    auth.profile = { id: 'user-1', role: 'admin' }

    await auth.signOut()

    expect(supabaseMock.auth.signOut).toHaveBeenCalled()
    expect(auth.user).toBeNull()
    expect(auth.profile).toBeNull()
    expect(auth.profileError).toBe('')
  })

  it('stores a generic profile error when the profile query fails', async () => {
    const auth = useAuthStore()
    auth.user = { id: 'user-1' }
    mockProfileQuery({ data: null, error: new Error('database connection detail') })
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {})

    await auth.loadProfile()

    expect(auth.profile).toBeNull()
    expect(auth.profileError).toMatch(/gagal dimuat/i)
    expect(auth.profileError).not.toContain('database connection detail')
    expect(consoleError).toHaveBeenCalled()
    expect(auth.profileLoading).toBe(false)
  })
})

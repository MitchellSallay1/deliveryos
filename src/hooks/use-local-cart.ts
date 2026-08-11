import { useCallback, useEffect, useState } from 'react'

/**
 * A pre-checkout draft cart kept in localStorage so a customer can browse a
 * store and build a cart without being forced to verify their phone first.
 * It is NOT authoritative — nothing here is trusted or reused for pricing
 * at submission. At checkout, once the customer is OTP-verified, these
 * items are pushed into a real server-side cart via the existing Phase A
 * cart RPCs (get_or_create_cart/add_cart_item), which is what
 * submit_commerce_order actually reads from.
 *
 * Scoped to a single store at a time, matching the single-vendor-per-cart
 * model — switching to a different store's page replaces the draft.
 */

export type LocalCartItem = {
  key: string
  productId: string
  selectedOptionIds: string[]
  quantity: number
}

type LocalCartState = {
  slug: string
  items: LocalCartItem[]
}

const STORAGE_KEY = 'deliveryos.commerce.local_cart'

function itemKey(productId: string, selectedOptionIds: string[]) {
  return `${productId}:${[...selectedOptionIds].sort().join(',')}`
}

function readState(slug: string): LocalCartState {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY)
    if (!raw) return { slug, items: [] }
    const parsed = JSON.parse(raw) as LocalCartState
    if (parsed.slug !== slug) return { slug, items: [] }
    return parsed
  } catch {
    return { slug, items: [] }
  }
}

function writeState(state: LocalCartState) {
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state))
}

export function useLocalCart(slug: string) {
  const [items, setItems] = useState<LocalCartItem[]>(() => readState(slug).items)

  useEffect(() => {
    setItems(readState(slug).items)
  }, [slug])

  const persist = useCallback(
    (next: LocalCartItem[]) => {
      setItems(next)
      writeState({ slug, items: next })
    },
    [slug],
  )

  const addItem = useCallback(
    (productId: string, quantity: number, selectedOptionIds: string[]) => {
      const key = itemKey(productId, selectedOptionIds)
      setItems((prev) => {
        const existing = prev.find((i) => i.key === key)
        const next = existing
          ? prev.map((i) => (i.key === key ? { ...i, quantity: i.quantity + quantity } : i))
          : [...prev, { key, productId, selectedOptionIds, quantity }]
        writeState({ slug, items: next })
        return next
      })
    },
    [slug],
  )

  const updateQuantity = useCallback(
    (key: string, quantity: number) => {
      setItems((prev) => {
        const next =
          quantity <= 0 ? prev.filter((i) => i.key !== key) : prev.map((i) => (i.key === key ? { ...i, quantity } : i))
        writeState({ slug, items: next })
        return next
      })
    },
    [slug],
  )

  const removeItem = useCallback(
    (key: string) => {
      setItems((prev) => {
        const next = prev.filter((i) => i.key !== key)
        writeState({ slug, items: next })
        return next
      })
    },
    [slug],
  )

  const clear = useCallback(() => {
    persist([])
  }, [persist])

  const itemCount = items.reduce((sum, i) => sum + i.quantity, 0)

  return { items, addItem, updateQuantity, removeItem, clear, itemCount }
}

import { describe, expect, it } from 'vitest'
import { NEXT_STATUS } from '@/utils/delivery-schemas'

describe('delivery status graph', () => {
  it('allows accept from assigned', () => {
    expect(NEXT_STATUS.assigned).toContain('accepted')
  })

  it('allows deliver from in_transit', () => {
    expect(NEXT_STATUS.in_transit).toContain('delivered')
  })
})

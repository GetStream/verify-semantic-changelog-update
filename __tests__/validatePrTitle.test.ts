import {describe, expect, it} from '@jest/globals'
import {validatePrTitle} from '../src/validatePrTitle.js'

describe('validatePrTitle', () => {
  it('reads the type, scope and subject', async () => {
    await expect(
      validatePrTitle('feat(ui): add a button', ['ui'])
    ).resolves.toEqual({
      type: 'feat',
      scopes: ['ui'],
      subject: 'add a button',
      breaking: false
    })
  })

  it('splits and trims several scopes', async () => {
    const result = await validatePrTitle('fix(llc, ui): stop a crash', [
      'llc',
      'ui'
    ])
    expect(result.scopes).toEqual(['llc', 'ui'])
  })

  it('accepts a title without a scope when no scopes are configured', async () => {
    const result = await validatePrTitle('chore: tidy up', undefined)
    expect(result.type).toBe('chore')
    expect(result.scopes).toBeUndefined()
  })

  it('marks `!` as breaking', async () => {
    const result = await validatePrTitle('feat(ui)!: remove a widget', ['ui'])
    expect(result.type).toBe('feat')
    expect(result.scopes).toEqual(['ui'])
    expect(result.breaking).toBe(true)
  })

  it('rejects a title without a type', async () => {
    await expect(validatePrTitle('add a button', undefined)).rejects.toThrow(
      'No release type found'
    )
  })

  it('rejects an unknown type', async () => {
    await expect(
      validatePrTitle('feature: add a button', undefined)
    ).rejects.toThrow('Unknown release type "feature"')
  })

  it('rejects a missing scope when scopes are configured', async () => {
    await expect(validatePrTitle('feat: add a button', ['ui'])).rejects.toThrow(
      'No scope found'
    )
  })

  it('lists the available types in the error', async () => {
    await expect(validatePrTitle('feature: x', undefined)).rejects.toThrow(
      ' - feat: A new feature'
    )
  })
})

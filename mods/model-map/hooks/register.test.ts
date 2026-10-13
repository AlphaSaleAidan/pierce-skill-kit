import { expect, test } from 'claude-code/testing'
import { describe as show, parse, remap } from './register'

test('maps an alias to the configured id and leaves others alone', () => {
  expect(remap('haiku', { haiku: 'claude-haiku-5-5' }, undefined)).toBe('claude-haiku-5-5')
  expect(remap('sonnet', { haiku: 'claude-haiku-5-5' }, undefined)).toBe('sonnet')
})

test('uses the default only when the call named no model', () => {
  expect(remap(undefined, {}, 'sonnet')).toBe('sonnet')
  expect(remap(undefined, {}, undefined)).toBeUndefined()
})

test('parses /models arguments', () => {
  expect(parse('set haiku claude-haiku-5-5')).toEqual({ cmd: 'set', a: 'haiku', b: 'claude-haiku-5-5' })
  expect(parse('').cmd).toBe('')
})

test('describes an empty map plainly', () => {
  expect(show({}, undefined)).toContain('empty')
})

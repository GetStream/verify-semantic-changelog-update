import {beforeEach, describe, expect, it, jest} from '@jest/globals'

interface File {
  filename: string
  status: string
  changes?: number
}

const inputs: Record<string, string> = {}
const setFailed = jest.fn<(message: string) => void>()
const warning = jest.fn<(message: string) => void>()
const info = jest.fn<(message: string) => void>()

let title = ''
let files: File[] = []
let eventName = 'pull_request_target'
let payload: Record<string, unknown> = {}

jest.unstable_mockModule('@actions/core', () => ({
  getInput: (name: string) => inputs[name] ?? '',
  getMultilineInput: (name: string) =>
    (inputs[name] ?? '').split('\n').filter(line => line !== ''),
  info,
  debug: jest.fn(),
  warning,
  setFailed
}))

const listFiles = Symbol('listFiles')
jest.unstable_mockModule('@actions/github', () => ({
  context: {
    get eventName() {
      return eventName
    },
    get payload() {
      return payload
    }
  },
  getOctokit: () => ({
    rest: {
      pulls: {
        get: async () => ({
          data: {title, head: {ref: 'feat/x'}, base: {ref: 'main'}}
        }),
        listFiles
      }
    },
    paginate: async (endpoint: unknown) => {
      expect(endpoint).toBe(listFiles)
      return files
    }
  })
}))

const {run} = await import('../src/run.js')

function failure(): string | undefined {
  return setFailed.mock.calls[0]?.[0]
}

describe('run', () => {
  beforeEach(() => {
    process.env.GITHUB_TOKEN = 't'
    for (const key of Object.keys(inputs)) delete inputs[key]
    inputs.types = 'fix\nfeat'
    inputs.path = 'changelog.md'
    inputs.scopes = JSON.stringify({llc: 'packages/llc', ui: 'packages/ui'})
    eventName = 'pull_request_target'
    payload = {
      pull_request: {number: 7, base: {user: {login: 'o'}, repo: {name: 'r'}}}
    }
    title = 'feat(ui): add a button'
    files = []
  })

  it('passes when the scope changelog is modified', async () => {
    files = [{filename: 'packages/ui/CHANGELOG.md', status: 'modified'}]
    await run()
    expect(failure()).toBeUndefined()
  })

  it('passes when the scope changelog is added', async () => {
    files = [{filename: 'packages/ui/CHANGELOG.md', status: 'added'}]
    await run()
    expect(failure()).toBeUndefined()
  })

  it('does not count a removed changelog', async () => {
    files = [{filename: 'packages/ui/CHANGELOG.md', status: 'removed'}]
    await run()
    expect(failure()).toContain('Missing: `packages/ui/changelog.md`')
  })

  it('counts a renamed changelog only when it was also edited', async () => {
    files = [
      {filename: 'packages/ui/CHANGELOG.md', status: 'renamed', changes: 0}
    ]
    await run()
    expect(failure()).toContain('Missing: `packages/ui/changelog.md`')

    setFailed.mockClear()
    files = [
      {filename: 'packages/ui/CHANGELOG.md', status: 'renamed', changes: 3}
    ]
    await run()
    expect(failure()).toBeUndefined()
  })

  it('does not count a mode-only change', async () => {
    files = [
      {filename: 'packages/ui/CHANGELOG.md', status: 'changed', changes: 0}
    ]
    await run()
    expect(failure()).toContain('Missing: `packages/ui/changelog.md`')
  })

  it.each(['./packages/ui', 'packages/ui/', './packages/ui/'])(
    'matches a scope path written as %s',
    async scopePath => {
      inputs.scopes = JSON.stringify({ui: scopePath})
      files = [{filename: 'packages/ui/CHANGELOG.md', status: 'modified'}]
      await run()
      expect(failure()).toBeUndefined()
    }
  )

  it.each(['', '.', './'])(
    'checks the top-level changelog for scope path "%s"',
    async scopePath => {
      inputs.scopes = JSON.stringify({ui: scopePath})
      files = [{filename: 'CHANGELOG.md', status: 'modified'}]
      await run()
      expect(failure()).toBeUndefined()
    }
  )

  it('lists every missing scope and says why', async () => {
    title = 'fix(llc, ui): stop a crash'
    files = [{filename: 'packages/ui/a.dart', status: 'modified'}]
    await run()
    expect(failure()).toBe(
      '`fix(llc, ui): stop a crash` is a `fix` change, so it must add an entry to every changelog it affects. Missing: `packages/llc/changelog.md` (scope `llc`), `packages/ui/changelog.md` (scope `ui`).'
    )
  })

  it('names a breaking change as the reason', async () => {
    title = 'chore(ui)!: drop a widget'
    files = [{filename: 'packages/ui/a.dart', status: 'modified'}]
    await run()
    expect(failure()).toContain('is a breaking change, so it must add')
  })

  it('checks the top-level changelog without a scope placeholder', async () => {
    delete inputs.scopes
    title = 'feat: add a button'
    files = [{filename: 'lib/a.dart', status: 'modified'}]
    await run()
    expect(failure()).toContain('Missing: `changelog.md`.')
    expect(failure()).not.toContain('scope')
  })

  it('skips a type that needs no changelog', async () => {
    title = 'chore(ui): tidy up'
    await run()
    expect(failure()).toBeUndefined()
    expect(info).toHaveBeenCalledWith(
      'Skipped: "chore(ui): tidy up" is not a type that needs a changelog entry.'
    )
  })

  it('warns about a scope missing from the scopes input', async () => {
    title = 'feat(uii): add a button'
    files = [{filename: 'packages/ui/a.dart', status: 'modified'}]
    await run()
    expect(failure()).toBeUndefined()
    expect(warning.mock.calls[0]?.[0]).toContain('Scope "uii" is not in the')
  })

  it('still checks the known scopes next to an unknown one', async () => {
    title = 'feat(uii, ui): add a button'
    files = [{filename: 'packages/ui/a.dart', status: 'modified'}]
    await run()
    expect(warning).toHaveBeenCalled()
    expect(failure()).toContain('(scope `ui`)')
  })

  it('skips when every scope in the title is unknown', async () => {
    title = 'feat(uii): add a button'
    await run()
    expect(failure()).toBeUndefined()
    expect(warning).toHaveBeenCalled()
    expect(info).toHaveBeenCalledWith(
      'Skipped: none of the scopes in the title has a changelog.'
    )
  })

  it('reports a pull request with no changes', async () => {
    await run()
    expect(failure()).toBe(
      'This pull request has no changes to check: every commit on `feat/x` is already on `main`. Push your changes, or close the pull request if they have already been merged.'
    )
  })

  it('says how to set a missing token', async () => {
    delete process.env.GITHUB_TOKEN
    await run()
    expect(failure()).toBe(
      'GITHUB_TOKEN is not set. Add `env: GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}` to this step.'
    )
  })

  it('names the scopes input when its JSON is invalid', async () => {
    inputs.scopes = '{ui: 1}'
    await run()
    expect(failure()).toMatch(/^The scopes input is not valid JSON: /)
  })

  it('names the event when it is not a pull request', async () => {
    eventName = 'push'
    payload = {}
    await run()
    expect(failure()).toBe(
      'This action only runs on pull_request or pull_request_target events, not push.'
    )
  })
})

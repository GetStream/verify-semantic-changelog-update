import conventionalCommitsConfig from 'conventional-changelog-conventionalcommits'
import conventionalCommitTypes from 'conventional-commit-types'
import {sync as parser} from 'conventional-commits-parser'

export async function validatePrTitle(
  prTitle: string,
  scopes: string[] | undefined
): Promise<{
  type: string
  scopes: string[] | undefined
  subject: string
  breaking: boolean
}> {
  const types = Object.keys(conventionalCommitTypes.types)

  const {parserOpts} = await conventionalCommitsConfig()
  const result = parser(prTitle, parserOpts)

  function printAvailableTypes(): string {
    return `Available types:\n${types
      .map(type => {
        let bullet = ` - ${type}`
        bullet += `: ${conventionalCommitTypes.types[type].description}`
        return bullet
      })
      .join('\n')}`
  }

  function isUnknownScope(s: string): boolean {
    if (scopes) return !scopes.includes(s)
    return false
  }

  if (!result.type) {
    throw new Error(
      `No release type found in pull request title "${prTitle}". Add a prefix to indicate what kind of release this pull request corresponds to. For reference, see https://www.conventionalcommits.org/\n\n${printAvailableTypes()}`
    )
  }

  if (!result.subject) {
    throw new Error(`No subject found in pull request title "${prTitle}".`)
  }

  if (!types.includes(result.type)) {
    throw new Error(
      `Unknown release type "${
        result.type
      }" found in pull request title "${prTitle}". \n\n${printAvailableTypes()}`
    )
  }

  if (scopes && !result.scope) {
    throw new Error(
      `No scope found in pull request title "${prTitle}". Use one of the available scopes: ${scopes.join(
        ', '
      )}.`
    )
  }

  let isBreakingChange = false
  if (result.notes) {
    isBreakingChange = (result.notes as {title: string; text: string}[]).some(
      note => note.title === 'BREAKING CHANGE'
    )
  }

  const givenScopes = result.scope
    ? (result.scope as string).split(',').map(scope => scope.trim())
    : undefined
  const unknownScopes = givenScopes ? givenScopes.filter(isUnknownScope) : []

  if (scopes && unknownScopes.length > 0) {
    throw new Error(
      `Unknown ${
        unknownScopes.length > 1 ? 'scopes' : 'scope'
      } "${unknownScopes.join(
        ','
      )}" found in pull request title "${prTitle}". Use one of the available scopes: ${scopes.join(
        ', '
      )}.`
    )
  }
  return {
    type: result.type,
    scopes: givenScopes,
    subject: result.subject,
    breaking: isBreakingChange
  }
}

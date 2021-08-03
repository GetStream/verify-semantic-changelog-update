import conventionalCommitsConfig from 'conventional-changelog-conventionalcommits'
import conventionalCommitTypes from 'conventional-commit-types'
import {sync as parser} from 'conventional-commits-parser'

export async function validatePrTitle(
  prTitle: string,
  scopes: string[]
): Promise<{
  type: string
  scopes: string[]
  subject: string
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
    return scopes && !scopes.includes(s)
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

  if (!result.scope) {
    throw new Error(
      `No scope found in pull request title "${prTitle}". Use one of the available scopes: ${scopes.join(
        ', '
      )}.`
    )
  }

  const givenScopes = (result.scope as string)
    .split(',')
    .map(scope => scope.trim())
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
  return {type: result.type, scopes: givenScopes, subject: result.subject}
}

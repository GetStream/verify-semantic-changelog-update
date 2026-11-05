import createPreset from 'conventional-changelog-conventionalcommits'
import conventionalCommitTypes from 'conventional-commit-types' with {type: 'json'}
import {CommitParser, type ParserOptions} from 'conventional-commits-parser'

export async function validatePrTitle(
  prTitle: string,
  scopes: string[] | undefined
): Promise<{
  type: string
  scopes: string[] | undefined
  subject: string
  breaking: boolean
}> {
  const commitTypes: Record<string, {description: string}> =
    conventionalCommitTypes.types
  const types = Object.keys(commitTypes)

  // The preset's typings declare `{}`; at runtime it carries the parser options.
  const {parser: parserOpts} = createPreset() as {parser: ParserOptions}
  const result = new CommitParser(parserOpts).parse(prTitle)

  function printAvailableTypes(): string {
    return `Available types:\n${types
      .map(type => {
        let bullet = ` - ${type}`
        bullet += `: ${commitTypes[type].description}`
        return bullet
      })
      .join('\n')}`
  }

  if (!result.type) {
    throw new Error(
      `No release type found in pull request title "${prTitle}". Add a prefix to indicate what kind of release this pull request corresponds to. For reference, see https://www.conventionalcommits.org/\n\n${printAvailableTypes()}`
    )
  }

  if (!result.subject) {
    throw new Error(
      `No subject found in pull request title "${prTitle}". Add a description after the colon, e.g. "fix(ui): stop a crash on scroll".`
    )
  }

  if (!types.includes(result.type)) {
    throw new Error(
      `Unknown release type "${
        result.type
      }" found in pull request title "${prTitle}".\n\n${printAvailableTypes()}`
    )
  }

  if (scopes && !result.scope) {
    throw new Error(
      `No scope found in pull request title "${prTitle}". Put a scope in parentheses after the type, e.g. "${result.type}(${scopes[0] ?? 'scope'}): ${result.subject}". Available scopes: ${scopes.join(
        ', '
      )}.`
    )
  }

  const givenScopes = result.scope
    ? result.scope.split(',').map(scope => scope.trim())
    : undefined

  const isBreakingChange = result.notes.some(
    note => note.title === 'BREAKING CHANGE'
  )

  return {
    type: result.type,
    scopes: givenScopes,
    subject: result.subject,
    breaking: isBreakingChange
  }
}

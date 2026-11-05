import * as core from '@actions/core'
import {context, getOctokit} from '@actions/github'
import {validatePrTitle} from './validatePrTitle.js'

interface Scopes {
  [key: string]: string
}

/**
 * Reads the `scopes` input: a JSON object from scope name to directory.
 */
function getScopesInput(): Scopes | undefined {
  const input = core.getInput('scopes')
  if (!input) return undefined
  try {
    return JSON.parse(input)
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error)
    throw new Error(`The scopes input is not valid JSON: ${reason}`)
  }
}

/**
 * Strips a leading `./` and trailing slashes, so `./packages/ui/` and
 * `packages/ui` name the same directory. `.` becomes the empty string.
 */
function normalizeDir(dir: string): string {
  return dir
    .replace(/^(\.\/)+/, '')
    .replace(/\/+$/, '')
    .replace(/^\.$/, '')
}

/**
 * Whether a changed file's new content differs: an added or modified file,
 * or a renamed or copied one that was also edited.
 */
function addsContent(file: {status: string; changes: number}): boolean {
  switch (file.status) {
    case 'added':
    case 'modified':
      return true
    case 'renamed':
    case 'copied':
      return file.changes > 0
    default:
      return false
  }
}

export async function run(): Promise<void> {
  try {
    const GITHUB_TOKEN = process.env.GITHUB_TOKEN
    if (!GITHUB_TOKEN) {
      throw new Error(
        'GITHUB_TOKEN is not set. Add `env: GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}` to this step.'
      )
    }
    const octokit = getOctokit(GITHUB_TOKEN)

    const types = core.getMultilineInput('types')
    const scopes = getScopesInput()
    const filePath = core.getInput('path')

    core.info(`Action types: ${types}`)
    if (scopes) core.info(`Action scopes: ${JSON.stringify(scopes, null, 4)}`)
    core.info(`Action filePath: ${filePath}`)

    // Debug log the payload.
    core.debug(`Payload keys: ${Object.keys(context.payload)}`)

    const contextPullRequest = context.payload.pull_request
    if (!contextPullRequest) {
      throw new Error(
        `This action only runs on pull_request or pull_request_target events, not ${context.eventName}.`
      )
    }

    const owner = contextPullRequest.base.user.login
    const repo = contextPullRequest.base.repo.name

    // The pull request info on the context isn't up to date. When
    // the user updates the title and re-runs the workflow, it would
    // be outdated. Therefore fetch the pull request via the REST API
    // to ensure we use the current title.
    const {data: pullRequest} = await octokit.rest.pulls.get({
      owner,
      repo,
      pull_number: contextPullRequest.number
    })

    // Validate if PrTitle is conventional and matches one of [types]
    const {
      type: prType,
      scopes: prScopes,
      breaking: prBreaking
    } = await validatePrTitle(
      pullRequest.title,
      scopes ? Object.keys(scopes) : undefined
    )

    const needsChangelog = prBreaking || types.includes(prType)

    core.info(`PR type: ${prType}`)
    if (prScopes) core.info(`PR scopes: ${prScopes}`)
    core.info(`PR needs a changelog entry: ${needsChangelog}`)

    if (!needsChangelog) {
      core.info(
        `Skipped: "${pullRequest.title}" is not a type that needs a changelog entry.`
      )
      return
    }

    // The changelogs this pull request has to update, each with the scope
    // that requires it.
    const required: Array<{path: string; scope?: string}> = []
    if (scopes && prScopes) {
      const unknownScopes = prScopes.filter(scope => !(scope in scopes))
      if (unknownScopes.length > 0) {
        core.warning(
          `Scope ${unknownScopes.map(s => `"${s}"`).join(', ')} is not in the scopes input, so its changelog is not checked. Known scopes: ${Object.keys(scopes).join(', ')}.`
        )
      }
      for (const scope of prScopes.filter(s => s in scopes)) {
        const scopePath = normalizeDir(scopes[scope])
        const path = scopePath !== '' ? `${scopePath}/${filePath}` : filePath
        required.push({path, scope})
      }
      if (required.length === 0) {
        core.info('Skipped: none of the scopes in the title has a changelog.')
        return
      }
    } else {
      required.push({path: filePath})
    }

    // The pull request's own file list holds every change since the branch
    // point, also when the base branch has moved on since then.
    const files = await octokit.paginate(octokit.rest.pulls.listFiles, {
      owner,
      repo,
      pull_number: contextPullRequest.number,
      per_page: 100
    })

    if (files.length === 0) {
      throw new Error(
        `This pull request has no changes to check: every commit on \`${pullRequest.head.ref}\` is already on \`${pullRequest.base.ref}\`. Push your changes, or close the pull request if they have already been merged.`
      )
    }

    const updated = new Set(
      files.filter(addsContent).map(file => file.filename.toUpperCase())
    )

    const missing = required.filter(
      ({path}) => !updated.has(path.toUpperCase())
    )
    if (missing.length > 0) {
      const reason = prBreaking
        ? 'is a breaking change'
        : `is a \`${prType}\` change`
      const list = missing
        .map(({path, scope}) =>
          scope ? `\`${path}\` (scope \`${scope}\`)` : `\`${path}\``
        )
        .join(', ')
      throw new Error(
        `\`${pullRequest.title}\` ${reason}, so it must add an entry to every changelog it affects. Missing: ${list}.`
      )
    }

    core.info(
      `Success: "${pullRequest.title}" updates ${required.map(({path}) => path).join(', ')}.`
    )
  } catch (error) {
    core.setFailed(error instanceof Error ? error.message : String(error))
  }
}

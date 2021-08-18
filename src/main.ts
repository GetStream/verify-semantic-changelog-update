import * as core from '@actions/core'
import {context, getOctokit} from '@actions/github'
import {validatePrTitle} from './validatePrTitle'
import assert from 'assert'

/**
 * Gets the values of an JSON input.
 *
 * @param     name     name of the input to get
 * @param     options  optional. See InputOptions.
 * @returns   Scopes
 *
 */
function getJsonInput(
  name: string,
  options?: core.InputOptions
): Scopes | undefined {
  const input = core.getInput(name, options)
  if (input) return JSON.parse(input)
}

interface Scopes {
  [key: string]: string
}

async function run(): Promise<void> {
  try {
    const GITHUB_TOKEN = process.env.GITHUB_TOKEN
    assert(GITHUB_TOKEN)
    const octokit = getOctokit(GITHUB_TOKEN)

    const types = core.getMultilineInput('types')
    const scopes = getJsonInput('scopes')
    const filePath = core.getInput('path')

    core.info(`Action types: ${types}`)
    if (scopes) core.info(`Action scopes: ${JSON.stringify(scopes, null, 4)}`)
    core.info(`Action filePath: ${filePath}`)

    // Debug log the payload.
    core.debug(`Payload keys: ${Object.keys(context.payload)}`)

    const contextPullRequest = context.payload.pull_request
    if (!contextPullRequest) {
      throw new Error(
        "This action can only be invoked in `pull_request_target` or `pull_request` events. Otherwise the pull request can't be inferred."
      )
    }

    const owner = contextPullRequest.base.user.login
    const repo = contextPullRequest.base.repo.name

    // The pull request info on the context isn't up to date. When
    // the user updates the title and re-runs the workflow, it would
    // be outdated. Therefore fetch the pull request via the REST API
    // to ensure we use the current title.
    const {data: pullRequest} = await octokit.pulls.get({
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

    const breaking = prBreaking || types.includes(prType)

    core.info(`PR type: ${prType}`)
    if (prScopes) core.info(`PR scopes: ${prScopes}`)
    core.info(`PR breaking: ${breaking}`)

    if (breaking) {
      // Define the base and head commits to be extracted from the context.
      const base = contextPullRequest?.base?.sha
      const head = contextPullRequest?.head?.sha

      // Log the base and head commits
      core.info(`Base commit: ${base}`)
      core.info(`Head commit: ${head}`)

      // Ensure that the base and head properties are set on the payload.
      if (!base || !head) {
        throw new Error(
          `The base and head commits are missing from the payload for this ${context.eventName} event. Please submit an issue on this action's GitHub repo.`
        )
      }

      // Use GitHub's compare two commits API.
      // https://developer.github.com/v3/repos/commits/#compare-two-commits
      const response = await octokit.repos.compareCommits({
        base,
        head,
        owner: context.repo.owner,
        repo: context.repo.repo
      })

      // Ensure that the request was successful.
      if (response.status !== 200) {
        throw new Error(
          `The GitHub API for comparing the base and head commits for this ${context.eventName} event returned ${response.status}, expected 200. Please submit an issue on this action's GitHub repo.`
        )
      }

      // Ensure that the head commit is ahead of the base commit.
      if (response.data.status !== 'ahead') {
        throw new Error(
          `The head commit for this ${context.eventName} event is not ahead of the base commit. Please submit an issue on this action's GitHub repo.`
        )
      }

      // Get the changed files from the response payload.
      const modifiedFiles = response.data.files?.filter(
        file => file.status === 'modified'
      )
      if (modifiedFiles) {
        const verifyChangelogModified = (
          fileName: string,
          scope = 'repo'
        ): void => {
          const changelogModified = modifiedFiles.some(
            file => file.filename === fileName
          )
          if (!changelogModified) {
            throw new Error(
              `File "${fileName}" of the pull request: "${pullRequest.title}" not updated for the scope "${scope}"`
            )
          }
        }

        if (scopes && prScopes) {
          const verifiableScopes = prScopes.filter(scope =>
            Object.keys(scopes).includes(scope)
          )
          for (const scope of verifiableScopes) {
            let path = filePath
            const scopePath = scopes[scope]
            if (scopePath !== '' && scopePath !== '.') {
              path = `${scopePath}/${filePath}`
            }
            verifyChangelogModified(path, scope)
          }
          core.info(
            `Success: Successfully verified pull request: "${pullRequest.title}"\nFound "${filePath}" updated in all these scopes: ${verifiableScopes}`
          )
        } else {
          verifyChangelogModified(filePath)
          core.info(
            `Success: Successfully verified pull request: "${pullRequest.title}"`
          )
        }
      }
    }
  } catch (error) {
    core.setFailed(error.message)
  }
}

run()

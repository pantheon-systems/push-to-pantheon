<?php
/**
 * Terminus Plugin that contain a collection of commands useful during
 * the build step on a [Pantheon](https://www.pantheon.io) site that uses
 * a GitHub PR workflow.
 *
 * See README.md for usage information.
 */

namespace Pantheon\TerminusBuildTools\Commands;

/**
 * Env Create Command
 */
class EnvCreateCommand extends BuildToolsBase
{

    /**
     * Create the specified multidev environment on the given Pantheon
     * site from the build assets at the current working directory.
     *
     * @command build:env:create
     * @aliases build-env:create
     * @param string $site_env_id The site and env of the SOURCE
     * @param string $multidev The name of the env to CREATE
     * @option label What to name the environment in commit comments
     * @option clone-content Run terminus env:clone-content if the environment is re-used
     * @option db-only Only clone the database when runing env:clone-content
     * @option message Commit message to include when committing assets to Pantheon
     * @option pr-id Post notification comment to a specific PR instead of the commit hash.
     * @option no-git-force set this flag to omit the --force flag from 'git add' and 'git push'
     */
    public function createBuildEnv(
        $site_env_id,
        $multidev,
        $options = [
            'label' => '',
            'clone-content' => false,
            'db-only' => false,
            'message' => '',
            'pr-id' =>  '',
            'no-git-force' =>  false,
        ])
    {
        list($site, $env) = $this->getSiteEnv($site_env_id);

        $env_label = $multidev;
        if (!empty($options['label'])) {
            $env_label = $options['label'];
        }

        $pr_id = $options['pr-id'];

        // Revert to build:env:push if build:env:create is run against dev.
        if ('dev' === $multidev) {
            $this->log()->notice('dev has been passed to the multidev option. Reverting to dev:env:push as dev is not a multidev environment.');
            // Run build:env:push.
            $this->pushCodeToPantheon($site_env_id, $multidev, '', $env_label, $options['message'], $options['git-force']);
            return;
        }

        if ($env->id === $multidev) {
            $this->log()->notice('Cannot create an environment from itself. Aborting.');
            return;
        }

        // Check to see if '$multidev' already exists on Pantheon.
        $environmentExists = $site->getEnvironments()->has($multidev);
        if (!$environmentExists) {
            $this->create($site_env_id, $multidev);
        }

        // If we did not create our environment, then run clone-content
        // instead -- but only if requested. No point in running 'clone'
        // if the user plans on re-installing Drupal.
        if ($environmentExists && $options['clone-content']) {
            $this->cloneContent($target, $env, $options['db-only']);
        }

        $this->pushCodeToPantheon($site_env_id, $multidev, '', $env_label, $options['message'], $options['no-git-force']);
    }
}

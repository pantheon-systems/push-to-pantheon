<?php
/**
 * Terminus Plugin that contain a collection of commands useful during
 * the build step on a [Pantheon](https://www.pantheon.io) site that uses
 * a Git PR workflow.
 *
 * See README.md for usage information.
 */

namespace Pantheon\TerminusBuildTools\Commands;

use Consolidation\OutputFormatters\StructuredData\RowsOfFields;
use Pantheon\Terminus\Commands\TerminusCommand;
use Pantheon\Terminus\Exceptions\TerminusException;
use Pantheon\Terminus\Site\SiteAwareInterface;
use Pantheon\Terminus\Site\SiteAwareTrait;
use Pantheon\TerminusBuildTools\Utility\UrlParsing;
use Symfony\Component\Filesystem\Filesystem;
use Symfony\Component\Finder\Finder;
use Robo\Common\ProcessUtils;
use Pantheon\Terminus\DataStore\FileStore;
use Pantheon\TerminusBuildTools\Credentials\CredentialManager;
use Pantheon\TerminusBuildTools\ServiceProviders\ProviderManager;
use Pantheon\Terminus\Commands\WorkflowProcessingTrait;
use Pantheon\Terminus\Models\Environment;

use Robo\Contract\BuilderAwareInterface;
use Robo\LoadAllTasks;

/**
 * Build Tool Base Command
 */
class BuildToolsBase extends TerminusCommand implements SiteAwareInterface, BuilderAwareInterface
{
    use LoadAllTasks; // uses TaskAccessor, which uses BuilderAwareTrait
    use SiteAwareTrait;
    use WorkflowProcessingTrait;

    const TRANSIENT_CI_DELETE_PATTERN = 'ci-';
    const PR_BRANCH_DELETE_PATTERN = 'pr-';
    const DEFAULT_DELETE_PATTERN = self::TRANSIENT_CI_DELETE_PATTERN;
    const DEFAULT_WORKFLOW_TIMEOUT = 180;

    protected $tmpDirs = [];

    protected $provider_manager;
    protected $ci_provider;
    protected $git_provider;
    protected $site_provider;

    /**
     * Constructor
     *
     * @param ProviderManager $provider_manager Provider manager may be injected for testing (not used). It is
     * not passed in by Terminus.
     */
    public function __construct($provider_manager = null)
    {
        $this->provider_manager = $provider_manager;
    }

    /**
     * Set GIT_SSH_COMMAND so we can disable strict host key checking. This allows builds to run without pauses
     * for user input.
     *
     * By not specifying a command in the hook below it will apply to any command from this class (or class that
     * extends this class, such as all of Build Tools).
     *
     * @hook init
     */
    public function noStrictHostKeyChecking()
    {
        // Set the GIT_SSH_COMMAND environment variable to avoid SSH Host Key prompt.
        // By using putenv, the environment variable won't persist past this PHP run.
        // Setting the Known Hosts File to /dev/null and the LogLevel to quiet prevents
        // this from persisting for a user regularly as well as the warning about adding
        // the SSH key to the known hosts file.
        putenv("GIT_SSH_COMMAND=ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=QUIET");
    }

    public function providerManager()
    {
        if (!$this->provider_manager) {
            // TODO: how can we do DI from within a Terminus Plugin? Huh?
            // Delayed initialization is one option.
            $credential_store = new FileStore($this->getConfig()->get('cache_dir') . '/build-tools');
            $credentialManager = new CredentialManager($credential_store);
            $credentialManager->setUserId($this->loggedInUserEmail());
            $this->provider_manager = new ProviderManager($credentialManager, $this->getConfig());
            $this->provider_manager->setLogger($this->logger);
        }
        return $this->provider_manager;
    }


    protected function getUrlFromBuildMetadata($site_name_and_env)
    {
        $buildMetadata = $this->retrieveBuildMetadata($site_name_and_env);
        return $this->getMetadataUrl($buildMetadata);
    }

    protected function getMetadataUrl($buildMetadata)
    {
        $site_name_and_env = $buildMetadata['site'];
        // Get the build metadata from the Pantheon site. Fail if there is
        // no build metadata on the master branch of the Pantheon site.
        $buildMetadata = $buildMetadata + ['url' => ''];
        if (empty($buildMetadata['url'])) {
            throw new TerminusException('The site {site} was not created with the build-env:create-project command; it therefore cannot be used with this command.', ['site' => $site_name_and_env]);
        }
        return $buildMetadata['url'];
    }

    protected function inferGitProviderFromUrl($url)
    {
        $provider = $this->providerManager()->inferProvider($url, \Pantheon\TerminusBuildTools\ServiceProviders\RepositoryProviders\GitProvider::class);
        if (!$provider) {
             throw new TerminusException('Could not figure out which git repository service to use with {url}.', ['url' => $url]);
        }
        $this->git_provider = $provider;
        return $provider;
    }

    /**
     * Get the email address of the user that is logged-in to Pantheon
     */
    protected function loggedInUserEmail()
    {
        if (!$this->session()->isActive()) {
            $this->log()->notice('No active session.');
            return;
        }

        $user_data = $this->session()->getUser()->fetch()->serialize();
        if (!array_key_exists('email', $user_data)) {
            $this->log()->notice('No email address in active session data.');
            return;
        }

        // Look up the email address of the active user (as auth:whoami does).
        return $user_data['email'];
    }

    /**
     * Return the sha of the HEAD commit.
     */
    protected function getHeadCommit($repositoryDir)
    {
        return exec("git -C $repositoryDir rev-parse HEAD");
    }

    /**
     * Run an env:clone-content operation
     * @param Environment $target
     * @param Environment $from_env
     * @param bool $db_only
     * @param bool $files_only
     */
    public function cloneContent(Environment $target, Environment $from_env, $db_only = false, $files_only = false)
    {
        if ($from_env->id === $target->id) {
            $this->log()->notice("Skipping clone since environments are the same.");
            return;
        }

        $from_name = $from_env->getName();

        // Clone files if we're only doing files, or if "only do db" is not set.
        if ($files_only || !$db_only) {
            $workflow = $target->cloneFiles($from_env);
            $this->log()->notice(
                "Cloning files from {from_name} environment to {target_env} environment",
                ['from_name' => $from_name, 'target_env' => $target->getName()]
            );
            while (!$workflow->checkProgress()) {
                // @TODO: Add Symfony progress bar to indicate that something is happening.
            }
            $this->log()->notice($workflow->getMessage());
        }

        // Clone database if we're only doing the database, or if "only do files" is not set.
        if ($db_only || !$files_only) {
            $workflow = $target->cloneDatabase($from_env);
            $this->log()->notice(
                "Cloning database from {from_name} environment to {target_env} environment",
                ['from_name' => $from_name, 'target_env' => $target->getName()]
            );
            while (!$workflow->checkProgress()) {
                // @TODO: Add Symfony progress bar to indicate that something is happening.
            }
            $this->log()->notice($workflow->getMessage());
        }
    }

    /**
     * Push code to Pantheon -- common routine used by 'create-project', 'create' and 'push-code' commands.
     */
    public function pushCodeToPantheon(
        $site_env_id,
        $multidev = '',
        $repositoryDir = '',
        $label = '',
        $message = '',
        $noGitForce = FALSE)
    {
        list($site, $env) = $this->getSiteEnv($site_env_id);
        $dev_env = $site->getEnvironments()->get('dev');
        $env_id = $env->getName();
        $multidev = empty($multidev) ? $env_id : $multidev;
        $branch = ($multidev == 'dev') ? 'master' : $multidev;
        $env_label = $multidev;
        if (!empty($label)) {
            $env_label = $label;
        }

        if (empty($message)) {
            $message = "Build assets for $env_label.";
        }

        if (empty($repositoryDir)) {
            $repositoryDir = getcwd();
        }

        // Sanity check: only push from directories that have .git and composer.json
        // Note: we might want to use push-to-pantheon even if there isn't a composer.json,
        // e.g. when using build:env:create with drops-7.
        foreach (['.git'] as $item) {
            if (!file_exists("$repositoryDir/$item")) {
                throw new TerminusException('Cannot push from {dir}: missing {item}.', ['dir' => $repositoryDir, 'item' => $item]);
            }
        }

        $this->log()->notice('Pushing code to {multidev} using branch {branch}.', ['multidev' => $multidev, 'branch' => $branch]);

        // Fetch the site id also
        $siteInfo = $site->serialize();
        $site_id = $siteInfo['id'];

        // Check to see if '$multidev' already exists on Pantheon.
        $environmentExists = $site->getEnvironments()->has($multidev);

        // Add a remote named 'pantheon' to point at the Pantheon site's git repository.
        // Skip this step if the remote is already there (e.g. due to CI service caching).
        $this->addPantheonRemote($dev_env, $repositoryDir);
        // $this->passthru("git -C $repositoryDir fetch pantheon");

        // Record the metadata for this build
        $metadata = $this->getBuildMetadata($repositoryDir);
        $this->recordBuildMetadata($metadata, $repositoryDir);

        // Drupal 7: Drush requires a settings.php file. Add one to the
        // build results if one does not already exist.
        $default_dir = "$repositoryDir/" . (is_dir("$repositoryDir/web") ? 'web/sites/default' : 'sites/default');
        $settings_file = "$default_dir/settings.php";
        if (is_dir($default_dir) && !is_file($settings_file)) {
          file_put_contents($settings_file, "<?php\n");
          $this->log()->notice('Created empty settings.php file {settingsphp}.', ['settingsphp' => $settings_file]);
        }

        // Remove any .git directories added by composer from the set of files
        // being committed. Ideally, there will be none. We cannot allow any to
        // remain, though, as git will interpret these as submodules, which
        // will prevent the contents of directories containing .git directories
        // from being added to the main repository.
        $finder = new Finder();
        $fs = new Filesystem();
        $fs->remove(
          $finder
            ->directories()
            ->in("$repositoryDir")
            ->ignoreDotFiles(false)
            ->ignoreVCS(false)
            ->depth('> 0')
            ->name('.git')
            ->getIterator()
        );

        // Create a new branch and commit the results from anything that may
        // have changed. We presume that the source repository is clean of
        // any unwanted files prior to the build step (e.g. after a clean
        // checkout in a CI environment.)
        $this->passthru("git -C $repositoryDir checkout -B $branch");
        if ($this->respectGitignore($repositoryDir) || $noGitForce === TRUE) {
            // In "Integrated Composer" mode, we will not commit ignored files
            $this->passthru("git -C $repositoryDir add .");
        }
        else {
            $this->passthru("git -C $repositoryDir add --force -A .");
        }

        // Now that everything is ready, commit the build artifacts.
        $this->passthru($this->interpolate("git -C {repositoryDir} commit -q -m [[message]]", ['repositoryDir' => $repositoryDir, 'message' => $message]));

        // If the environment does exist, then we need to be in git mode
        // to push the branch up to the existing multidev site.
        if ($environmentExists) {
            $target = $site->getEnvironments()->get($multidev);
            $this->connectionSet($target, 'git');
        }

        // Push the branch to Pantheon
        $preCommitTime = time();
        $forceFlag = $noGitForce ? "" : "--force";
        $this->passthru("git -C $repositoryDir push $forceFlag -q pantheon $branch");

        // If the environment already existed, then we risk encountering
        // a race condition, because the 'git push' above will fire off
        // an asynchronous update of the existing update. If we switch to
        // sftp mode before this sync is completed, then the converge that
        // sftp mode kicks off will corrupt the environment.
        if ($environmentExists) {
            $this->waitForCodeSync($preCommitTime, $site, $multidev);
        }

        return $metadata;
    }

    /**
     * respectGitignore determines if we should respoect the .gitignore
     * file (rather than use 'git add --force). This is experimental.
     */
    protected function respectGitignore($repositoryDir)
    {
        if ($this->checkIntegratedComposerSetting("$repositoryDir/pantheon.yml", false)) {
            return false;
        }
        return $this->checkIntegratedComposerSetting("$repositoryDir/pantheon.yml", true)
            || $this->checkIntegratedComposerSetting("$repositoryDir/pantheon.upstream.yml", true);
    }

    /**
     * checkIntegratedComposerSetting checks if the build step switch is on
     * in just one (pantheon.yml or pantheon.upstream.yml) config file.
     */
    private function checkIntegratedComposerSetting($pantheonYmlPath, $desiredValue)
    {
        if (!file_exists($pantheonYmlPath)) {
            return false;
        }
        $contents = file_get_contents($pantheonYmlPath);

        $expected = $desiredValue ? 'true' : 'false';

        // build_step_demo: true
        //  - or -
        // build_step: true
        return preg_match("#^build_step(_demo)?: $expected\$#m", $contents);
    }

    /**
     * projectFromRemoteUrl converts from a url e.g. https://github.com/org/repo
     * to the "org/repo" portion of the provided url.
     */
    protected function projectFromRemoteUrl($url)
    {
        $org_user = UrlParsing::orgUserFromRemoteUrl($url);
        $repository = UrlParsing::repositoryFromRemoteUrl($url);
        return "$org_user/$repository";
    }

    protected function deleteEnv($env, $deleteBranch = false)
    {
        $workflow = $env->delete(
            ['delete_branch' => true,]
        );
        $this->processWorkflow($workflow);
        $this->log()->notice('Deleted the multidev environment {env}.', ['env' => $env->id,]);
    }

    /**
     * Return a list of multidev environments matching the provided
     * pattern, sorted with oldest first.
     *
     * @param string $site_id Site to check.
     * @param string $multidev_delete_pattern Regex of environments to select.
     */
    protected function oldestEnvironments($site_id, $multidev_delete_pattern)
    {
        // Get a list of all of the sites
        $env_list = $this->getSite($site_id)->getEnvironments()->serialize();

        // Filter out the environments that do not match the multidev delete pattern
        $env_list = array_filter(
            $env_list,
            function ($item) use ($multidev_delete_pattern) {
                return preg_match("%$multidev_delete_pattern%", $item['id']);
            }
        );

        // Sort the environments by creation date, with oldest first
        uasort(
            $env_list,
            function ($a, $b) {
                if ($a['created'] == $b['created']) {
                    return 0;
                }
                return ($a['created'] < $b['created']) ? -1 : 1;
            }
        );

        return $env_list;
    }

    /**
     * Create a new multidev environment
     *
     * @param string $site_env Source site and environment.
     * @param string $multidev Name of environment to create.
     */
    public function create($site_env, $multidev)
    {
        list($site, $env) = $this->getSiteEnv($site_env, 'dev');
        $this->log()->notice("Creating multidev {env} for site {site}", ['site' => $site->getName(), 'env' => $multidev]);
        $workflow = $site->getEnvironments()->create($multidev, $env);
        while (!$workflow->checkProgress()) {
            // This line was not in the original build tools. It had a blank todo.
            $this->log()->notice("Creating multidev {env} for site {site}", ['site' => $site->getName(), 'env' => $multidev]);
            sleep(5);
        }
        $this->log()->notice($workflow->getMessage());
    }

    /**
     * Set the connection mode to 'sftp' or 'git' mode, and wait for
     * it to complete.
     *
     * @param Pantheon\Terminus\Models\Environment $env
     * @param string $mode
     */
    public function connectionSet($env, $mode)
    {
        // Refresh environment data.
        $env->fetch();
        if ($mode === $env->get('connection_mode')) {
            return;
        }
        $workflow = $env->changeConnectionMode($mode);
        if (is_string($workflow)) {
            $this->log()->notice($workflow);
        } else {
            while (!$workflow->checkProgress()) {
                // TODO: Add workflow progress output
            }
            $this->log()->notice($workflow->getMessage());
        }
    }

    /**
     * Wait for a workflow to complete.
     *
     * @param int $startTime Ignore any workflows that started before the start time.
     * @param string $workflow The workflow message to wait for.
     */
    protected function waitForCodeSync($startTime, $site, $env_name)
    {
        $this->waitForWorkflow($startTime, $site, $env_name);
    }

    protected function waitForWorkflow($startTime, $site, $env_name, $expectedWorkflowDescription = '', $maxWaitInSeconds = null, $maxNotFoundAttempts = null)
    {
        if (empty($expectedWorkflowDescription)) {
            $expectedWorkflowDescription = "Sync code on $env_name";
        }

        if (null === $maxWaitInSeconds) {
            $maxWaitInSecondsEnv = getenv('TERMINUS_BUILD_TOOLS_WORKFLOW_TIMEOUT');
            $maxWaitInSeconds = $maxWaitInSecondsEnv ? $maxWaitInSecondsEnv : self::DEFAULT_WORKFLOW_TIMEOUT;
        }

        $startWaiting = time();
        $firstWorkflowDescription = null;
        $notFoundAttempts = 0;
        $workflows = $site->getWorkflows();

        while(true) {
            $site = $this->getsite($site->id);
            // Refresh env on each interation.
            $index = 0;
            $workflows->reset();
            $workflow_items = $workflows->fetch(['paged' => false,])->all();
            $found = false;
            foreach ($workflow_items as $workflow) {
                $workflowCreationTime = $workflow->get('created_at');

                $workflowDescription = str_replace('"', '', $workflow->get('description'));
                if ($index === 0) {
                    $firstWorkflowDescription = $workflowDescription;
                }
                $index++;

                if ($workflowCreationTime < $startTime) {
                    // We already passed the start time.
                    break;
                }

                if (($expectedWorkflowDescription === $workflowDescription)) {
                    $workflow->fetch();
                    $this->log()->notice("Workflow '{current}' {status}.", ['current' => $workflowDescription, 'status' => $workflow->getStatus(), ]);
                    $found = true;
                    if ($workflow->isSuccessful()) {
                        $this->log()->notice("Workflow succeeded");
                        return;
                    }
                }
            }
            if (!$found) {
                $notFoundAttempts++;
                $this->log()->notice("Current workflow is '{current}'; waiting for '{expected}'", ['current' => $firstWorkflowDescription, 'expected' => $expectedWorkflowDescription]);
                if ($maxNotFoundAttempts && $notFoundAttempts === $maxNotFoundAttempts) {
                    $this->log()->warning("Attempted '{max}' times, giving up waiting for workflow to be found", ['max' => $maxNotFoundAttempts]);
                    break;
                }
            }
            // Wait a bit, then spin some more
            sleep(5);
            if (time() - $startWaiting >= $maxWaitInSeconds) {
                $this->log()->warning("Waited '{max}' seconds, giving up waiting for workflow to finish", ['max' => $maxWaitInSeconds]);
                break;
            }
        }
    }

    /**
     * Return the metadata for this build.
     *
     * @return string[]
     */
    public function getBuildMetadata($repositoryDir)
    {
        $buildMetadata = [
          'url'         => $this->sanitizeUrl(exec("git -C $repositoryDir config --get remote.origin.url")),
          'ref'         => exec("git -C $repositoryDir rev-parse --abbrev-ref HEAD"),
          'sha'         => $this->getHeadCommit($repositoryDir),
          'comment'     => exec("git -C $repositoryDir log --pretty=format:%s -1"),
          'commit-date' => exec("git -C $repositoryDir show -s --format=%ci HEAD"),
          'build-date'  => date("Y-m-d H:i:s O"),
        ];

        if (!isset($this->git_provider)) {
            $this->git_provider = $this->inferGitProviderFromUrl($buildMetadata['url']);
        }

        $this->git_provider->alterBuildMetadata($buildMetadata);

        return $buildMetadata;
    }

    /**
     * Sanitize a build url: if http[s] is used, strip any token that exists.
     *
     * @param string $url
     * @return string
     */
    protected function sanitizeUrl($url)
    {
        return preg_replace('#://[^@/]*@#', '://', $url);
    }

    /**
     * Write the build metadata into the build results prior to committing them.
     *
     * @param string[] $metadata
     */
    public function recordBuildMetadata($metadata, $repositoryDir)
    {
        $buildMetadataFile = "$repositoryDir/build-metadata.json";
        $metadataContents = json_encode($metadata, JSON_UNESCAPED_SLASHES);
        $this->log()->notice('Set {file} to {metadata}.', ['metadata' => $metadataContents, 'file' => basename($buildMetadataFile)]);

        file_put_contents($buildMetadataFile, $metadataContents);
    }

    /**
     * Iterate through the different environments, and keep fetching their
     * metadata until we find one that has a 'url' component.
     *
     * @param string $site_id The site to operate on
     * @param stirng[] $oldestEnvironments List of environments
     * @return string
     */
    protected function retrieveRemoteUrlFromBuildMetadata($site_id, $oldestEnvironments)
    {
        foreach ($oldestEnvironments as $env) {
            try {
                $metadata = $this->retrieveBuildMetadata("{$site_id}.{$env}");
                if (!empty($metadata['url'])) {
                    return $metadata['url'];
                }
            }
            catch(\Exception $e) {
            }
        }
        return '';
    }

    /**
     * Get the build metadata from a remote site.
     *
     * @param string $site_env_id
     * @return string[]
     */
    public function retrieveBuildMetadata($site_env_id)
    {
        $src = ':code/build-metadata.json';
        $dest = '/tmp/build-metadata.json';

        $status = $this->rsync($site_env_id, $src, $dest);
        if ($status == 0) {
            $metadataContents = file_get_contents($dest);
            $metadata = json_decode($metadataContents, true);
        }

        $metadata['site'] = $site_env_id;

        @unlink($dest);

        return $metadata;
    }

    /**
     * Add or refresh the 'pantheon' remote
     */
    public function addPantheonRemote($env, $repositoryDir)
    {
        // Refresh the remote is already there (e.g. due to CI service caching), just in
        // case. If something changes, this info is NOT removed by "rebuild without cache".
        if ($this->hasPantheonRemote($repositoryDir)) {
            passthru("git -C $repositoryDir remote remove pantheon");
        }
        $connectionInfo = $env->connectionInfo();
        $gitUrl = $connectionInfo['git_url'];
        $this->passthru("git -C $repositoryDir remote add pantheon $gitUrl");
    }

    /**
     * Check to see if there is a remote named 'pantheon'
     */
    protected function hasPantheonRemote($repositoryDir)
    {
        exec("git -C $repositoryDir remote show", $output);
        return array_search('pantheon', $output) !== false;
    }

    /**
     * Substitute replacements in a string. Replacements should be formatted
     * as {key} for raw value, or [[key]] for shell-escaped values.
     *
     * @param string $message
     * @param string[] $context
     * @return string[]
     */
    protected function interpolate($message, array $context)
    {
        // build a replacement array with braces around the context keys
        $replace = array();
        foreach ($context as $key => $val) {
            if (!is_array($val) && (!is_object($val) || method_exists($val, '__toString'))) {
                $replace[sprintf('{%s}', $key)] = $val;
                $replace[sprintf('[[%s]]', $key)] = ProcessUtils::escapeArgument($val);
            }
        }

        // interpolate replacement values into the message and return
        return strtr($message, $replace);
    }

    /**
     * Call rsync to or from the specified site.
     *
     * @param string $site_env_id Remote site
     * @param string $src Source path to copy from. Start with ":" for remote.
     * @param string $dest Destination path to copy to. Start with ":" for remote.
     * @param boolean $ignoreIfNotExists Silently fail and do not return error if remote source does not exist.
     */
    protected function rsync($site_env_id, $src, $dest, $ignoreIfNotExists = true)
    {
        list($site, $env) = $this->getSiteEnv($site_env_id);
        $env_id = $env->getName();

        $siteInfo = $site->serialize();
        $site_id = $siteInfo['id'];

        $siteAddress = "$env_id.$site_id@appserver.$env_id.$site_id.drush.in:";

        $src = preg_replace('/^:/', $siteAddress, $src);
        $dest = preg_replace('/^:/', $siteAddress, $dest);

        $this->log()->notice('Rsync {src} => {dest}', ['src' => $src, 'dest' => $dest]);
        $status = 0;
        $command = "rsync -rlIvz --ipv4 --exclude=.git -e 'ssh -p 2222 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=QUIET' $src $dest >/dev/null 2>&1";
        passthru($command, $status);
        if (!$ignoreIfNotExists && in_array($status, [0, 23]))
        {
            throw new TerminusException('Command `{command}` failed with exit code {status}', ['command' => $command, 'status' => $status]);
        }

        return $status;
    }

    /**
     * Call passthru; throw an exception on failure.
     *
     * @param string $command
     */
    protected function passthru($command, $loggedCommand = '')
    {
        $result = 0;
        $loggedCommand = empty($loggedCommand) ? $command : $loggedCommand;
        // TODO: How noisy do we want to be?
        $this->log()->notice("Running {cmd}", ['cmd' => $loggedCommand]);
        passthru($command, $result);

        if ($result != 0) {
            throw new TerminusException('Command `{command}` failed with exit code {status}', ['command' => $loggedCommand, 'status' => $result]);
        }
    }

    function passthruRedacted($command, $secret)
    {
        $loggedCommand = str_replace($secret, 'REDACTED', $command);
        $command .= " | sed -e 's/$secret/REDACTED/g'";

        return $this->passthru($command, $loggedCommand);
    }

    /**
     * Call exec; throw an exception on failure.
     *
     * @param string $command
     * @return string[]
     */
    protected function exec($command)
    {
        $result = 0;
        $this->log()->notice("Running {cmd}", ['cmd' => $command]);
        exec($command, $outputLines, $result);

        if ($result != 0) {
            throw new TerminusException('Command `{command}` failed with exit code {status}', ['command' => $command, 'status' => $result]);
        }
        return $outputLines;
    }
}

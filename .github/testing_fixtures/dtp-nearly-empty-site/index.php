<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Push to Pantheon Deployment Test</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;600&display=swap" rel="stylesheet">
    <style>
        body, html {
            height: 100%;
            margin: 0;
            font-family: 'Poppins', sans-serif;
            background-color: white;
            color: rgb(35, 35, 45);
            display: flex;
            justify-content: center;
            align-items: center;
            text-align: center;
        }
        .container {
            max-width: 600px;
            padding: 2rem;
        }
        .logo {
            width: 200px;
            margin-bottom: 2rem;
        }
        h1 {
            font-weight: 600;
            font-size: 1.75rem;
            margin-bottom: 2rem;
        }
        .status-box {
            padding: 1.5rem;
            border-radius: 8px;
            background-color: #f8f9fa;
            border: 1px solid #e9ecef;
        }
        .status-box p {
            margin: 0;
            font-size: 1.1rem;
        }
        a {
            color: rgb(95, 65, 229);
            text-decoration: none;
            font-weight: 600;
            display: inline-flex;
            align-items: center;
            gap: 0.25rem;
        }
        .pds-icon {
            width: 0.8em;
            height: 0.8em;
        }
        a:hover {
            text-decoration: underline;
        }
        footer {
            margin-top: 3rem;
            font-size: 0.9rem;
            color: #6c757d;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <img src="https://pantheon.io/themes/custom/pagoda/pantheon-logo.svg" alt="Pantheon Logo" class="logo">
            <h1>Push to Pantheon Deployment Test</h1>
        </header>
        <main>
            <div class="status-box">
                <?php
                    // Set Pragma header to prevent caching
                    header('Pragma: no-cache');

                    $host = $_SERVER['HTTP_HOST'];
                    $repo_url = 'https://github.com/pantheon-systems/push-to-pantheon';
                    $site_uuid = '1cd0c63b-c463-4d84-8d6b-e1f538c0a3de';
                    $dashboard_base_url = "https://dashboard.pantheon.io/sites/{$site_uuid}#";

                    $pr_pattern = '/^pr-(\d+)-/';
                    $standard_env_pattern = '/^(dev|test|live)-/';

                    $svg_icon = '<svg xmlns="http://www.w3.org/2000/svg" role="img" viewBox="0 0 320 512" fill="none" aria-hidden="true" focusable="false" class="pds-icon"><path d="M278.6 233.4c12.5 12.5 12.5 32.8 0 45.3l-160 160c-12.5 12.5-32.8 12.5-45.3 0s-12.5-32.8 0-45.3L210.7 256 73.4 118.6c-12.5-12.5-12.5-32.8 0-45.3s32.8-12.5 45.3 0l160 160z" fill="currentColor"></path></svg>';

                    if (preg_match($pr_pattern, $host, $matches)) {
                        $pr_number = $matches[1];
                        $link = "{$repo_url}/pull/{$pr_number}";
                        echo "<p><a href='{$link}' target='_blank' rel='noopener noreferrer'>View Pull Request #{$pr_number} on GitHub {$svg_icon}</a></p>";
                    } elseif (!preg_match($standard_env_pattern, $host) && strpos($host, 'dtp-nearly-empty-site') !== false) {
                        $parts = explode('-', $host);
                        $multidev_name = $parts[0];
                        $link = "{$dashboard_base_url}{$multidev_name}";
                        echo "<p><a href='{$link}' target='_blank' rel='noopener noreferrer'>View Multidev Environment on Pantheon Dashboard {$svg_icon}</a></p>";
                    } else {
                        $link = $repo_url;
                        echo "<p><a href='{$link}' target='_blank' rel='noopener noreferrer'>View Repository on GitHub {$svg_icon}</a></p>";
                    }
                ?>
            </div>
        </main>
        <footer>
            <p>Powered by <a href="https://pantheon.io">Pantheon</a></p>
        </footer>
    </div>
</body>
</html>

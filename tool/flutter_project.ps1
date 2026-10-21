param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('run', 'build-web', 'build-apk', 'build-appbundle', 'analyze', 'test')]
  [string] $Action,
  [string] $Device = 'chrome',
  [string[]] $FlutterArgs = @()
)

$ErrorActionPreference = 'Stop'

# CargoKit's Windows batch helper looks in %HOME%\.cargo\bin. Rustup uses
# %USERPROFILE% by default, while Windows shells often leave HOME unset.
if ($env:OS -eq 'Windows_NT' -and $env:USERPROFILE) {
  if ([string]::IsNullOrWhiteSpace($env:HOME)) {
    $env:HOME = $env:USERPROFILE
  }

  $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
  if (Test-Path (Join-Path $cargoBin 'cargo.exe')) {
    $env:Path = "$cargoBin;$env:Path"
  }
}

# Java's Windows NIO selector uses a Unix-domain socket whose path must stay
# short. C:\tmp avoids the long/virtualized TEMP path used by this workspace.
if ($env:OS -eq 'Windows_NT' -and
    ($Action -in @('build-apk', 'build-appbundle') -or
      ($Action -eq 'run' -and $Device -notin @('chrome', 'web-server')))) {
  $socketTemp = Join-Path $env:SystemDrive 'tmp'
  if (-not (Test-Path -LiteralPath $socketTemp -PathType Container)) {
    throw "Android builds need the short socket temp directory '$socketTemp' in this Windows environment."
  }

  if ($env:JAVA_TOOL_OPTIONS -notmatch '(^|\s)-Djdk\.net\.unixdomain\.tmpdir=') {
    $socketTempForJava = $socketTemp.Replace('\', '/')
    $socketOption = "-Djdk.net.unixdomain.tmpdir=$socketTempForJava"
    $env:JAVA_TOOL_OPTIONS = (@($env:JAVA_TOOL_OPTIONS, $socketOption) -join ' ').Trim()
  }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot 'supabase/project_configs.json'
$flutterCommand = Get-Command flutter.bat -ErrorAction SilentlyContinue
$flutter = if ($flutterCommand) {
  $flutterCommand.Source
} else {
  'C:\Users\sjhong.DESKTOP-5G0NPTO\develop\flutter\bin\flutter.bat'
}

if (-not (Test-Path -LiteralPath $flutter)) {
  throw "Flutter SDK not found at the configured path: $flutter"
}

$defineArgs = @()
if ($Action -in @('run', 'build-web', 'build-apk', 'build-appbundle')) {
  if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Supabase config not found: $configPath"
  }
  $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
  if (-not ($config.projectUrl -is [string]) -or -not ($config.publishableKey -is [string]) -or
      [string]::IsNullOrWhiteSpace($config.projectUrl) -or [string]::IsNullOrWhiteSpace($config.publishableKey)) {
    throw 'Supabase config must contain non-empty projectUrl and publishableKey values.'
  }
  $defineArgs = @(
    "--dart-define=SUPABASE_URL=$($config.projectUrl)",
    "--dart-define=SUPABASE_ANON_KEY=$($config.publishableKey)"
  )
}

Push-Location $repoRoot
try {
  switch ($Action) {
    'run' { & $flutter run -d $Device @defineArgs @FlutterArgs }
    'build-web' { & $flutter build web @defineArgs @FlutterArgs }
    'build-apk' { & $flutter build apk @defineArgs @FlutterArgs }
    'build-appbundle' { & $flutter build appbundle @defineArgs @FlutterArgs }
    'analyze' { & $flutter analyze @FlutterArgs }
    'test' { & $flutter test @FlutterArgs }
  }
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
  Pop-Location
}

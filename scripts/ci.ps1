$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repositoryRoot

if (-not (Get-Command forge -ErrorAction SilentlyContinue)) {
    throw "forge is required on PATH"
}

if (-not (Test-Path -LiteralPath "lib\forge-std\src\Test.sol")) {
    forge install --no-git --shallow foundry-rs/forge-std
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

forge fmt --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
forge build --deny warnings --sizes
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$env:FOUNDRY_PROFILE = "ci"
forge test --deny warnings --no-match-path "tests/private/**"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

npm ci --ignore-scripts
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
npm run ci:sdk
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
npm run check:loc
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

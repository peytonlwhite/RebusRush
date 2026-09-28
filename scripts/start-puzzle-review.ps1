$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (-not (Test-Path -LiteralPath 'functions/node_modules/firebase-admin')) {
    & npm ci --prefix functions
    if ($LASTEXITCODE -ne 0) { throw 'Could not install review dependencies.' }
}
& npx --yes --package=firebase-tools@15.31.0 -c 'npm run puzzles:review --prefix functions'

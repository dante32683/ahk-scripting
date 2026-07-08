param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,

    [string]$WorkingDirectory = (Get-Location).Path,

    [ValidateSet("Review", "Explore", "Edit")]
    [string]$Mode = "Review",

    [string]$Model = ""
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command gemini -ErrorAction SilentlyContinue)) {
    throw "Gemini CLI was not found on PATH."
}

$modeInstruction = switch ($Mode) {
    "Review" {
        "Read-only review. Do not modify files. Focus on concrete findings, risks, missing tests, and verification gaps."
    }
    "Explore" {
        "Read-only exploration. Do not modify files. Summarize relevant structure, files, and likely next steps."
    }
    "Edit" {
        "Edit-capable draft mode. Work in the Gemini-created worktree only. Keep changes minimal and report changed files."
    }
}

$fullPrompt = @"
You are acting as a bounded Gemini side helper for Codex on a local software project.

Rules:
- $modeInstruction
- Codex is the primary implementer and verifier.
- Do not invent facts. If uncertain, say so.
- Prefer concise, concrete output.
- When discussing code, include file paths and line numbers when relevant.
- Separate findings from assumptions.
- Do not claim tests passed unless you ran them.
- If reviewing code, prioritize bugs, regressions, missing tests, and risky assumptions.

Working directory:
$WorkingDirectory

Task:
$Prompt
"@

Push-Location -LiteralPath $WorkingDirectory
try {
    $arguments = @("--skip-trust", "--output-format", "text", "--approval-mode")

    if ($Mode -eq "Edit") {
        $arguments += @("auto_edit", "--worktree")
    } else {
        $arguments += "plan"
    }

    if ($Model -ne "") {
        $arguments += @("--model", $Model)
    }

    $arguments += @("-p", $fullPrompt)
    & gemini @arguments
} finally {
    Pop-Location
}

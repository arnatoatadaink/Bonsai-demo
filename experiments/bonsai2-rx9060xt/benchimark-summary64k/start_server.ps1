# Windows PowerShell: launch one model on RX 9070 XT via Vulkan.
# Requires compatible PrismML llama.cpp for PQ2_0 models.
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('bonsai8','gemma12','qwen9')]
    [string]$Model,
    [Parameter(Mandatory=$true)]
    [string]$LlamaServer,
    [string]$GpuDevice = '',
    [int]$Port = 8080
)
$ErrorActionPreference = 'Stop'
$paths = @{
    bonsai8 = 'D:\lmstudio_models\prism-ml\Ternary-Bonsai-8B-gguf\Ternary-Bonsai-8B-PQ2_0.gguf'
    gemma12 = 'D:\lmstudio_models\unsloth\gemma-4-12b-it-GGUF\gemma-4-12B-it-qat-UD-Q4_K_XL.gguf'
    qwen9 = 'D:\lmstudio_models\unsloth\Qwen3.5-9B-MTP-GGUF\Qwen3.5-9B-UD-Q4_K_XL.gguf'
}
if (-not (Test-Path -LiteralPath $LlamaServer -PathType Leaf)) {
    throw "llama-server executable not found: $LlamaServer"
}
if (-not (Test-Path -LiteralPath $paths[$Model] -PathType Leaf)) {
    throw "GGUF not found: $($paths[$Model])"
}
if (-not $GpuDevice) {
    Write-Host 'GPU device selection required. Listing Vulkan devices:' -ForegroundColor Yellow
    & $LlamaServer --list-devices
    throw 'Rerun with -GpuDevice VulkanN where VulkanN is the RX 9070 XT (do not assume the index).'
}
Write-Host "Target: $Model / $GpuDevice / 65536 context / q8_0 K+V / MTP OFF"
Write-Host 'Check startup log for real device name, full context allocation, cache types and offload.'
$launchArgs = @(
    '-m', $paths[$Model],
    '--host', '127.0.0.1', '--port', "$Port",
    '--device', $GpuDevice,
    '-ngl', '99', '-sm', 'none',
    '-c', '65536',
    '--cache-type-k', 'q8_0',
    '--cache-type-v', 'q8_0',
    '-fa', 'on',
    '-np', '1',
    '--jinja'
)
# No draft model / speculative decoding parameters: MTP OFF.
# Do NOT globally set --reasoning-budget 0: ON/OFF is tested per request,
# subject to runtime/template support and manual verification.
& $LlamaServer @launchArgs
if ($LASTEXITCODE -ne 0) { throw "llama-server exited with code $LASTEXITCODE" }

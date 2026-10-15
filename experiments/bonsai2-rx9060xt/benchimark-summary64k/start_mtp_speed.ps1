# Separate baseline / MTP launcher for RX 9070 XT Vulkan.
# Validate the selected device and backend option support before use.
param(
 [Parameter(Mandatory=$true)][string]$LlamaServer,
 [ValidateSet('qwen9','gemma12','gemma26')][string]$Model,
 [ValidateSet('baseline','mtp')][string]$Mode='baseline',
 [string]$Device='',
 [int]$Port=18080,
 [int]$DraftNMax=4
)
$ErrorActionPreference='Stop'
$models=@{
 qwen9=@{target='D:\lmstudio_models\unsloth\Qwen3.5-9B-MTP-GGUF\Qwen3.5-9B-UD-Q4_K_XL.gguf';draft='';method='embedded'}
 gemma12=@{target='D:\lmstudio_models\unsloth\gemma-4-12b-it-GGUF\gemma-4-12B-it-qat-UD-Q4_K_XL.gguf';draft='D:\lmstudio_models\unsloth\gemma-4-12b-it-GGUF\gemma-4-12B-it-Q8_0-MTP.gguf';method='separate'}
 gemma26=@{target='D:\lmstudio_models\unsloth\gemma-4-26B-A4B-it-qat-GGUF\gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf';draft='D:\lmstudio_models\unsloth\gemma-4-26B-A4B-it-qat-GGUF\gemma-4-26B-A4B-it-Q8_0-MTP.gguf';method='separate'}
}
$cfg=$models[$Model]
if(!(Test-Path -LiteralPath $LlamaServer -PathType Leaf)){throw "Missing llama-server: $LlamaServer"}
if(!(Test-Path -LiteralPath $cfg.target -PathType Leaf)){throw "Missing target: $($cfg.target)"}
if($Mode -eq 'mtp' -and $cfg.method -eq 'separate' -and !(Test-Path -LiteralPath $cfg.draft -PathType Leaf)){throw "Missing draft: $($cfg.draft)"}
$listing=(& $LlamaServer --list-devices 2>&1 | Out-String)
Write-Host $listing
if(!$Device){
 $found=@($listing -split '\r?\n' | Where-Object {$_ -match 'RX\s*9070\s*XT'} | ForEach-Object {if($_ -match '\b(Vulkan\d+)\b'){$Matches[1]}} | Select-Object -Unique)
 if($found.Count -ne 1){throw "Unable to identify unique RX 9070 XT VulkanN device"}
 $Device=$found[0]
}
if(!(@($listing -split '\r?\n' | Where-Object {$_ -match [regex]::Escape($Device) -and $_ -match 'RX\s*9070\s*XT'}).Count -eq 1)){throw "Device not verified as RX 9070 XT"}
$helpText=(& $LlamaServer --help 2>&1 | Out-String)
if($Mode -eq 'mtp'){
 foreach($flag in @('--spec-type','--spec-draft-n-max')){
  if(!$helpText.Contains($flag)){throw "Unsupported option: $flag"}
 }
 if($cfg.method -eq 'separate' -and !$helpText.Contains('--model-draft')){throw "Backend does not list --model-draft"}
}
$launch=@('-m',$cfg.target,'--host','127.0.0.1','--port',"$Port",'--device',$Device,
 '-ngl','99','-sm','none','-c','65536','--cache-type-k','q8_0','--cache-type-v','q8_0','-fa','on','-np','1','--jinja')
if($Mode -eq 'mtp'){
 $launch+=@('--spec-type','draft-mtp','--spec-draft-n-max',"$DraftNMax")
 if($cfg.method -eq 'separate'){$launch+=@('--model-draft',$cfg.draft)}
}
Write-Host "Model=$Model Mode=$Mode GPU=$Device DraftNMax=$DraftNMax"
Write-Host "Verify actual MTP initialization and draft acceptance from runtime logs."
& $LlamaServer @launch
if($LASTEXITCODE -ne 0){throw "llama-server exited code $LASTEXITCODE"}

# install-sync.ps1 — تركيب المزامنة التلقائية لموقع The Sniper على الـVPS (مرة واحدة)
# التشغيل: انقر بالزر الأيمن على الملف ← Run with PowerShell
# أو من PowerShell:  powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\install-sync.ps1"

$ErrorActionPreference = "Stop"
$Repo   = "https://github.com/malmohamad1995-ctrl/the-sniper.git"
$Site   = "C:\TheSniper"
$Task   = "TheSniper-Sync"

function Step($t) { Write-Host "`n== $t" -ForegroundColor Yellow }

Step "1) فحص Git"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git غير مثبت، جاري التثبيت..."
    winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "لم يكتمل تثبيت Git. ثبّته من https://git-scm.com/download/win ثم شغّل هذا الملف مرة أخرى." -ForegroundColor Red
        Read-Host "اضغط Enter للخروج"; exit 1
    }
}
git --version

Step "2) تنزيل الموقع إلى $Site"
if (Test-Path "$Site\.git") { git -C $Site remote set-url origin $Repo } else { git clone $Repo $Site }
git -C $Site config user.name  "The Sniper"
git -C $Site config user.email "noreply@thesniper.invalid"

Step "3) أول مزامنة (قد تفتح نافذة تسجيل دخول GitHub مرة واحدة فقط)"
& powershell -ExecutionPolicy Bypass -File "$Site\sync\sync-sniper.ps1" -SiteRepo $Site
if ($LASTEXITCODE -ne 0) { Write-Host "فشلت أول مزامنة. صوّر هذه النافذة وأرسلها." -ForegroundColor Red; Read-Host "اضغط Enter للخروج"; exit 1 }

Step "4) جدولة المزامنة كل 5 دقائق"
$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Site\sync\sync-sniper.ps1`" -SiteRepo `"$Site`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$princ   = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive
$set     = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 4) -StartWhenAvailable
Register-ScheduledTask -TaskName $Task -Action $action -Trigger $trigger -Principal $princ -Settings $set -Force | Out-Null
Write-Host "تمت جدولة المهمة: $Task"

Write-Host "`nتم التركيب. الموقع سيتحدث تلقائياً عند كل صفقة جديدة." -ForegroundColor Green
Read-Host "اضغط Enter للإغلاق"

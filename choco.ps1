# Установка Chocolatey (если не установлен)
if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Chocolatey не найден. Устанавливаю..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
} else {
    Write-Host "Chocolatey уже установлен."
}

# Список пакетов для установки
$packages = @(
    "googlechrome",
    "firefox",
    "7zip",
    "git",
    "vscode",
    "notepadplusplus",
    "dotnet-sdk",
    "python",
    "nodejs-lts"
)

# Установка пакетов
foreach ($pkg in $packages) {
    Write-Host "Устанавливаю $pkg..."
    choco install $pkg -y --ignore-checksums
}

# Проверка
Write-Host "Установленные пакеты:"
choco list --local-only

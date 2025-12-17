# 默认情况下，Windows PowerShell 的执行策略为 Restricted，不允许运行任何脚本。
# 按住 Shift，右键-在此处打开 PowerShell 窗口
# 查看当前执行策略：Get-ExecutionPolicy
# 修改执行策略（当前用户有效）：Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
# 确认执行策略为 RemoteSigned，选中这个脚本文件，右键-使用 PowerShell 运行

# PowerShell 5.1 版本对 UTF-8 中文支持不友好，中文解析报错，导致脚本不能正常执行，所以脚本编码使用的是 ANSI
# 查看版本：Get-Host | Select-Object Version

# 脚本自动修补只对【家庭/学校免费版】有效，其他专业收费版本无效
# https://www.xshell.com/zh/free-for-home-school/

# 教程出处：https://www.52pojie.cn/thread-1714055-1-1.html

function Repair-BinaryFile {
    param(
        [string]$FilePath,
        [string]$SearchHex,
        [string]$ReplaceHex,
        [switch]$ReplaceAll
    )

    # 验证文件存在
    if (-not (Test-Path $FilePath)) {
        #Write-Error "文件不存在: $FilePath"
        Write-Host "文件不存在: $FilePath" -ForegroundColor Cyan
        return
    }
    Write-Host "正在修补文件: $FilePath" -ForegroundColor Green

    # 创建备份
    $backupPath = Create-Backup -FilePath $FilePath

    # 转换十六进制为字节数组
    $SearchHex = $SearchHex -replace '\s',''
    $ReplaceHex = $ReplaceHex -replace '\s',''

    if ($SearchHex.Length -ne $ReplaceHex.Length) {
        throw "搜索和替换的十六进制字符串长度必须相同"
    }
    if ($SearchHex.Length % 2 -ne 0) {
        throw "十六进制字符串长度必须是偶数"
    }

    $searchBytes = for ($i = 0; $i -lt $SearchHex.Length; $i += 2) {
        [Convert]::ToByte($SearchHex.Substring($i, 2), 16)
    }

    $replaceBytes = for ($i = 0; $i -lt $ReplaceHex.Length; $i += 2) {
        [Convert]::ToByte($ReplaceHex.Substring($i, 2), 16)
    }

    Write-Host "开始直接修补文件..." -ForegroundColor Yellow
    Write-Host "搜索: $SearchHex" -ForegroundColor Cyan
    Write-Host "替换: $ReplaceHex" -ForegroundColor Cyan
    Write-Host "模式: $(if ($ReplaceAll) { '替换所有匹配项' } else { '替换第一个匹配项' })" -ForegroundColor Cyan

    # 执行直接替换
    $matchesFound = SearchAndReplaceBinary -FilePath $FilePath -SearchBytes $searchBytes -ReplaceBytes $replaceBytes -ReplaceAll:$ReplaceAll

    if ($matchesFound -gt 0) {
        Write-Host "修补完成! 共替换了 $matchesFound 个匹配项" -ForegroundColor Green
        Write-Host "原文件备份: $backupPath" -ForegroundColor Cyan
    } else {
        Write-Host "未找到匹配的字节序列" -ForegroundColor Yellow
        <#
        if (Test-Path $backupPath) {
            Remove-Item $backupPath -Force
            Write-Host "原文件备份已删除: $backupPath" -ForegroundColor Cyan
        }
        #>
    }
}

function SearchAndReplaceBinary {
    param(
        [string]$FilePath,
        [byte[]]$SearchBytes,
        [byte[]]$ReplaceBytes,
        [bool]$ReplaceAll
    )

    $searchLength = $SearchBytes.Length
    $matchesFound = 0

    # 以读写方式打开文件
    $stream = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)

    try {
        $buffer = New-Object byte[] (64KB)  # 64KB缓冲区足够
        $fileLength = $stream.Length
        $position = 0

        while ($position -lt $fileLength) {
            # 计算要读取的字节数
            $bytesToRead = [Math]::Min($buffer.Length, $fileLength - $position)

            # 读取数据到缓冲区
            $bytesRead = $stream.Read($buffer, 0, $bytesToRead)

            if ($bytesRead -eq 0) { break }

            # 在缓冲区中搜索
            for ($i = 0; $i -le $bytesRead - $searchLength; $i++) {
                $isMatch = $true
                for ($j = 0; $j -lt $searchLength; $j++) {
                    if ($buffer[$i + $j] -ne $SearchBytes[$j]) {
                        $isMatch = $false
                        break
                    }
                }

                if ($isMatch) {
                    # 计算文件中的绝对位置
                    $matchPosition = $position + $i

                    # 定位并写入替换数据
                    $stream.Seek($matchPosition, [System.IO.SeekOrigin]::Begin) | Out-Null
                    $stream.Write($ReplaceBytes, 0, $ReplaceBytes.Length)

                    Write-Host "在位置 0x$($matchPosition.ToString('X8')) 找到匹配并替换" -ForegroundColor Green
                    $matchesFound++

                    # 恢复读取位置
                    $stream.Seek($position + $bytesRead, [System.IO.SeekOrigin]::Begin) | Out-Null

                    if (-not $ReplaceAll) {
                        return $matchesFound
                    }
                }
            }

            $position += $bytesRead

            # 显示进度
            $percentComplete = [Math]::Round(($position / $fileLength) * 100, 2)
            Write-Progress -Activity "处理文件" -Status "已扫描 $position/$fileLength 字节" -PercentComplete $percentComplete
        }

        Write-Progress -Activity "处理文件" -Completed
    }
    finally {
        $stream.Close()
    }

    return $matchesFound
}

function Create-Backup() {
    param(
        [string]$FilePath
    )

    #$backupPath = "$FilePath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $backupPath = Get-Backup-Path -FilePath $FilePath
    if (Test-Path $backupPath) {
        Write-Host "原文件备份已存在: $backupPath" -ForegroundColor Cyan
        return $backupPath
    }
    Write-Host "正在创建备份..." -ForegroundColor Yellow
    Copy-Item $FilePath $backupPath -Force
    Write-Host "备份已创建: $backupPath" -ForegroundColor Green

    return $backupPath
}

function Get-Backup-Path() {
    param(
        [string]$FilePath
    )

    return $FilePath + "0000";
}

function Get-Install-Path-Parent() {
    #$xshellExe = Get-Command -Name "Xshell" | Select-Object -ExpandProperty Source
    $xshellExe = (Get-Command -Name "Xshell").Source # D:\Program Files (x86)\NetSarang\Xshell 8\Xshell.exe
    if ($xshellExe) {
        $installDir = Split-Path -Path $xshellExe -Parent # D:\Program Files (x86)\NetSarang\Xshell 8
        $parentDir = Split-Path -Path $installDir -Parent # D:\Program Files (x86)\NetSarang
    } else {
        $xshellExe = $pwd
        #Write-Host "脚本所在路径：$pwd" -ForegroundColor Gray
        if ($xshellExe) {
            $installDir = Split-Path -Path $xshellExe # D:\Program Files (x86)\NetSarang
            #Write-Host "installDir：$installDir" -ForegroundColor Gray
            $parentDir = $installDir
        }
    }

    if (-not ($parentDir -match "NetSarang")) {
        throw "请确认系统环境变量 Path 中存在程序安装路径，或者将脚本文件放在 Xshell 的安装目录下，并确保安装目录上级为 NetSarang"
    }

    # 最终返回程序安装父级目录：D:\Program Files (x86)\NetSarang\
    return $parentDir + "\"
}

function Show-ExitMessage {
    Write-Host "脚本执行完成，按任意键退出..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# 设置错误处理，报错后不再往下执行
#$ErrorActionPreference = "Stop"

# 修补程序
$xshell7 = $true
$xftp7 = $true
$xshell8 = $true
$xftp8 = $true

# 主程序入口【需要放在函数定义之后】
try {

    $installPath = Get-Install-Path-Parent
    Write-Host "程序安装父级目录：$installPath" -ForegroundColor Gray

    # Xshell 7.0.x
    if ($xshell7) { 
        $fPath = $installPath + "Xshell 7\"
        $fName = "Xshell.exe"
        # 去除授权登录弹窗
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "75 45 6A 07 6A" -ReplaceHex "EB 45 6A 07 6A"
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "74 E3 6A 01 6A" -ReplaceHex "EB E3 6A 01 6A"
        $fName = "nslicense.dll"
        # 去除强制更新弹窗
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "0F 85 BA 00 00 00 57 56" -ReplaceHex "E9 BB 00 00 00 90 57 56"
        $fName = "nsutil2.dll"
        # 去除检查更新、终止支持弹窗提示
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "0F 84 89 04 00 00 50" -ReplaceHex "E9 8A 04 00 00 90 50"
    }
    # Xftp 7.0.x
    if ($xftp7) { 
        $fPath = $installPath + "Xftp 7\"
        $fName = "Xftp.exe"
        # 去除授权登录弹窗
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "75 45 6A 07 6A" -ReplaceHex "EB 45 6A 07 6A"
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "74 E3 6A 01 6A" -ReplaceHex "EB E3 6A 01 6A"
        $fName = "nslicense.dll"
        # 去除强制更新弹窗
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "0F 85 BA 00 00 00 57 56" -ReplaceHex "E9 BB 00 00 00 90 57 56"
        $fName = "nsutil2.dll"
        # 去除检查更新、终止支持弹窗提示
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "0F 84 89 04 00 00 50" -ReplaceHex "E9 8A 04 00 00 90 50"
    }

    # Xshell 8.0.x
    if ($xshell8) { 
        $fPath = $installPath + "Xshell 8\"
        $fName = "Xshell.exe"
        # 去除授权登录弹窗
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "75 45 6A 08 6A" -ReplaceHex "EB 45 6A 08 6A"
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "74 E3 6A 01 6A" -ReplaceHex "EB E3 6A 01 6A"
        # 去除启动时检查更新及系统通知
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "85C074146A006A00" -ReplaceHex "85C0EB146A006A00" # 空格分隔符不影响
        $fName = "nslicense.dll"
        # 去除强制更新弹窗
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "0F 85 BA 00 00 00 57 56" -ReplaceHex "E9 BB 00 00 00 90 57 56"
        $fName = "nsutil2.dll"
        # 去除检查更新、终止支持弹窗提示
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "0F 84 86 00 00 00 50" -ReplaceHex "E9 87 00 00 00 90 50"
    }

    # Xftp 8.0.x
    if ($xftp8) { 
        $fPath = $installPath + "Xftp 8\"
        $fName = "Xftp.exe"
        # 去除授权登录弹窗
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "75 45 6A 08 6A" -ReplaceHex "EB 45 6A 08 6A"
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "74 E3 6A 01 6A" -ReplaceHex "EB E3 6A 01 6A"
        # 去除启动时检查更新及系统通知
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "85C074146A006A00" -ReplaceHex "85C0EB146A006A00" # 空格分隔符不影响
        $fName = "nslicense.dll"
        # 去除强制更新弹窗
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "0F 85 BA 00 00 00 57 56" -ReplaceHex "E9 BB 00 00 00 90 57 56"
        $fName = "nsutil2.dll"
        # 去除检查更新、终止支持弹窗提示
        Repair-BinaryFile -FilePath ($fPath + $fName) -SearchHex "0F 84 86 00 00 00 50" -ReplaceHex "E9 87 00 00 00 90 50"
    }

} catch {
    Write-Host "错误: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "堆栈跟踪: $($_.Exception.StackTrace)" -ForegroundColor Red
} finally {
    Show-ExitMessage
}

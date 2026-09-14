<#
.SYNOPSIS
Read-only probe for Windows Autopilot Device Preparation Device Association UEFI state.

.DESCRIPTION
Enables SeSystemEnvironmentPrivilege in the current process and checks the known
DeviceLink UEFI variables without returning their raw contents. Intended for
full Windows and AMD64 WinPE validation.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if (-not ('WindowsDeviceLink.FirmwareReader' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace WindowsDeviceLink {
    public static class FirmwareReader {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern uint GetFirmwareEnvironmentVariable(
            string lpName,
            string lpGuid,
            byte[] pBuffer,
            uint nSize
        );
    }

    public static class TokenPrivilege {
        [StructLayout(LayoutKind.Sequential)]
        public struct LUID {
            public uint LowPart;
            public int HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct TOKEN_PRIVILEGES {
            public uint PrivilegeCount;
            public LUID Luid;
            public uint Attributes;
        }

        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);

        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool AdjustTokenPrivileges(
            IntPtr TokenHandle,
            bool DisableAllPrivileges,
            ref TOKEN_PRIVILEGES NewState,
            uint BufferLength,
            IntPtr PreviousState,
            IntPtr ReturnLength
        );

        public static void Enable(string privilege) {
            const uint TOKEN_ADJUST_PRIVILEGES = 0x20;
            const uint TOKEN_QUERY = 0x8;
            const uint SE_PRIVILEGE_ENABLED = 0x2;

            IntPtr token;
            if (!OpenProcessToken(
                System.Diagnostics.Process.GetCurrentProcess().Handle,
                TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY,
                out token))
                throw new System.ComponentModel.Win32Exception();

            LUID luid;
            if (!LookupPrivilegeValue(null, privilege, out luid))
                throw new System.ComponentModel.Win32Exception();

            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
            tp.PrivilegeCount = 1;
            tp.Luid = luid;
            tp.Attributes = SE_PRIVILEGE_ENABLED;

            if (!AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero))
                throw new System.ComponentModel.Win32Exception();
        }
    }
}
"@
}

[WindowsDeviceLink.TokenPrivilege]::Enable('SeSystemEnvironmentPrivilege')

$namespace = '{B3DE75DA-819C-4FD5-9F01-C3D49E8CBBD7}'
$variables = @(
    'DeviceLinkId',
    'DeviceLinkJwtCompressed',
    'DeviceLinkJwtLastWrite',
    'DeviceLinkCreationTimeUtc'
)

$environment = if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { 'WindowsPE' } else { 'Windows' }

foreach ($name in $variables) {
    $buffer = New-Object byte[] 65536
    $size = [WindowsDeviceLink.FirmwareReader]::GetFirmwareEnvironmentVariable(
        $name,
        $namespace,
        $buffer,
        $buffer.Length
    )

    $lastError = if ($size -eq 0) {
        [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    }
    else {
        $null
    }

    [pscustomobject]@{
        Environment = $environment
        Namespace   = $namespace
        Name        = $name
        Present     = ($size -gt 0)
        Size        = [int]$size
        LastError   = $lastError
    }
}
